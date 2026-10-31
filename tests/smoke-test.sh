#!/usr/bin/env bash
# Smoke test: builds a real tunnel between an OpenVPN server and a client,
# both running the image under test, and pings through it.
#
# Usage: tests/smoke-test.sh <image> [expected OpenVPN version] [expected iptables version]
# Needs docker, openssl and /dev/net/tun on the host. Uses sudo (if not root)
# to hand the client config to root, as recommended in the README.
set -euo pipefail

IMAGE="${1:?usage: $0 <image> [version]}"
VERSION="${2:-}"
IPTABLES_VERSION="${3:-}"
NET=openvpn-smoke
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO=sudo

WORK="$(mktemp -d)"
cleanup() {
    docker rm -f vpn-smoke-client vpn-smoke-server >/dev/null 2>&1 || true
    docker network rm "${NET}" >/dev/null 2>&1 || true
    ${SUDO} rm -rf "${WORK}"
}
trap cleanup EXIT

dump_logs() {
    echo "--- server log"; docker logs vpn-smoke-server 2>&1 || true
    echo "--- client log"; docker logs vpn-smoke-client 2>&1 || true
}

echo "== Version"
# openvpn --version exits with 1, so don't let that fail the test
(docker run --rm "${IMAGE}" --version || true) | tee "${WORK}/version.txt"
if [ -n "${VERSION}" ]; then
    grep -q "^OpenVPN ${VERSION} " "${WORK}/version.txt"
fi

echo "== iptables"
docker run --rm --entrypoint iptables "${IMAGE}" -V | tee "${WORK}/iptables.txt"
if [ -n "${IPTABLES_VERSION}" ]; then
    grep -q "^iptables v${IPTABLES_VERSION} " "${WORK}/iptables.txt"
fi
docker run --rm --cap-add NET_ADMIN --entrypoint iptables "${IMAGE}" -L -n

echo "== Certificates"
mkdir -p "${WORK}/pki" "${WORK}/server" "${WORK}/client"
cd "${WORK}/pki"
ec=(-newkey ec -pkeyopt ec_paramgen_curve:prime256v1)
openssl req -x509 "${ec[@]}" -nodes -keyout ca.key -out ca.crt -days 1 \
    -subj /CN=smoke-ca 2>/dev/null

printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth\n' > server.ext
printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=clientAuth\n' > client.ext

openssl req "${ec[@]}" -nodes -keyout server.key -out server.csr \
    -subj /CN=vpn-smoke-server 2>/dev/null
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days 1 -extfile server.ext -out server.crt 2>/dev/null

# The client key is encrypted, like in the README (--askpass client.pwd)
echo "smoke-secret" > client.pwd
openssl req "${ec[@]}" -passout file:client.pwd -keyout client.key -out client.csr \
    -subj /CN=vpn-smoke-client 2>/dev/null
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -days 1 -extfile client.ext -out client.crt 2>/dev/null

cp ca.crt server.crt server.key "${WORK}/server/"
cp ca.crt client.crt client.key client.pwd "${WORK}/client/"
cat > "${WORK}/client/client.ovpn" <<CONF
client
dev tun
proto udp
remote vpn-smoke-server 1194
nobind
persist-key
persist-tun
ca ca.crt
cert client.crt
key client.key
remote-cert-tls server
verb 3
CONF
# Root-owned and private, as recommended in the README for cap_drop: ALL
chmod 600 "${WORK}/client/"*
${SUDO} chown -R 0:0 "${WORK}/client"
chmod 644 "${WORK}/server/"*

echo "== Server"
docker network create "${NET}" >/dev/null
docker run -d --name vpn-smoke-server --network "${NET}" \
    --cap-add NET_ADMIN --device /dev/net/tun \
    -v "${WORK}/server:/vpn:ro" \
    "${IMAGE}" \
    --dev tun --proto udp --port 1194 \
    --server 10.8.0.0 255.255.255.0 --topology subnet \
    --ca ca.crt --cert server.crt --key server.key --dh none --verb 3 >/dev/null

echo "== Client (hardened, as in docker-compose.yaml)"
docker run -d --name vpn-smoke-client --network "${NET}" \
    --cap-drop ALL --cap-add NET_ADMIN --device /dev/net/tun \
    --read-only --tmpfs /tmp --tmpfs /run \
    --security-opt no-new-privileges:true \
    --health-interval 2s --health-start-period 60s \
    -v "${WORK}/client:/vpn:ro" \
    "${IMAGE}" \
    --config client.ovpn --askpass client.pwd --auth-nocache >/dev/null

echo "== Waiting for the client to become healthy"
status=""
for _ in $(seq 60); do
    status="$(docker inspect --format '{{.State.Health.Status}}' vpn-smoke-client 2>/dev/null || echo gone)"
    [ "${status}" = "healthy" ] && break
    [ "${status}" = "gone" ] && break
    sleep 1
done
if [ "${status}" != "healthy" ]; then
    echo "::error::client did not become healthy (status: ${status})"
    dump_logs
    exit 1
fi

echo "== Ping through the tunnel"
if ! docker run --rm --network container:vpn-smoke-client --entrypoint ping \
        "${IMAGE}" -c 3 -W 2 10.8.0.1; then
    echo "::error::no ping through the tunnel"
    dump_logs
    exit 1
fi

echo "== Clean shutdown on SIGTERM"
docker stop --timeout 10 vpn-smoke-client >/dev/null
code="$(docker inspect --format '{{.State.ExitCode}}' vpn-smoke-client)"
dump_logs
if [ "${code}" = "137" ]; then
    echo "::error::client was killed instead of stopping on SIGTERM"
    exit 1
fi
echo "Smoke test passed"
