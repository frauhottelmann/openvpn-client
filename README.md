[![Docker Image CI](https://github.com/frauhottelmann/openvpn-client/actions/workflows/docker.yml/badge.svg)](https://github.com/frauhottelmann/openvpn-client/actions/workflows/docker.yml)

# OpenVPN client in a Docker container

- originally forked from ekristen
- OpenVPN (and iptables for up/down scripts) from the stable Alpine repositories
- multi-arch images for `linux/amd64`, `linux/arm64`, `linux/arm/v7` and `linux/arm/v6`
- built, smoke-tested with a real tunnel and scanned for vulnerabilities on GitHub Actions
- health check that turns `healthy` once the tunnel interface is up

## Image tags

Images are published to `ghcr.io/frauhottelmann/openvpn-client`.

| Tag | Built from |
| --- | --- |
| `latest` | the most recent release (git tag) |
| `2.7.5`, `2.7`, `2` | a release, named after the OpenVPN version in Alpine |
| `edge` | the latest commit on `master`, rebuilt weekly for Alpine security fixes |
| `sha-<commit>` | a specific commit on `master` |

## Setup

1. Put your client config into a directory, e.g. `./client/client.ovpn`, together
   with any files it references (`ca`, `cert`, `key`, ...). Relative paths in
   the config are resolved against `/vpn` inside the container.
2. If the private key is protected by a password, put the password into
   `./client/client.pwd`.
3. Make the files readable for root only. The hardened example below drops all
   capabilities, so root in the container cannot read files owned by another
   user with mode `600`:

   ```sh
   sudo chown -R root:root ./client
   sudo chmod 600 ./client/*
   ```

## docker run

```sh
docker run -d --name vpn-client \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  -v "$PWD/client:/vpn:ro" \
  ghcr.io/frauhottelmann/openvpn-client:latest \
  --config client.ovpn --askpass client.pwd --auth-nocache
```

Everything after the image name is passed to `openvpn`. `--auth-nocache` is
recommended so that OpenVPN does not keep the password in memory.

## Docker Compose example

Hardened setup: only `NET_ADMIN`, read-only root filesystem, config mounted
read-only.

```yaml
name: openvpn
services:
  openvpn-client:
    image: ghcr.io/frauhottelmann/openvpn-client:latest
    container_name: openvpn-client
    restart: unless-stopped
    command: --config /vpn/client.ovpn --askpass /vpn/client.pwd --auth-nocache
    volumes:
      - ./client/:/vpn:ro
    devices:
      - "/dev/net/tun:/dev/net/tun"
    cap_drop:
      - ALL
    cap_add:
      - NET_ADMIN
    read_only: true
    tmpfs:
      - /tmp
      - /run  # iptables keeps its lock file here
    security_opt:
      - no-new-privileges:true
    network_mode: "bridge"
```

If your config uses `user`/`group` to drop privileges, also add `SETUID` and
`SETGID` to `cap_add`. If the VPN pushes IPv6, add
`sysctls: ["net.ipv6.conf.all.disable_ipv6=0"]`.

## Route other containers through the VPN

Containers that share the network namespace of the VPN client use its routes.

With `docker run`:

```sh
docker run -it --rm \
  --network container:vpn-client \
  alpine:3 sh
```

With Docker Compose, in the same file as `openvpn-client`:

```yaml
  app:
    image: alpine:3
    command: sleep infinity
    network_mode: service:openvpn-client
    depends_on:
      openvpn-client:
        condition: service_healthy
```

Ports of `app` have to be published on the `openvpn-client` service.

## Notes

- `docker stop` sends `SIGTERM`, so OpenVPN shuts down cleanly and notifies
  the server (with `explicit-exit-notify` in the config).
- The smoke test in `tests/smoke-test.sh` can be run locally:
  `docker build -t openvpn-client:test . && tests/smoke-test.sh openvpn-client:test`
