FROM alpine:3

# Package versions from the Alpine repositories. "~=" accepts any package
# revision (e.g. 2.7.7-r0, 2.7.7-r1), so Alpine rebuilds don't break the build.
# OPENVPN_VERSION must match the git tag of a release.
ARG OPENVPN_VERSION=2.7.7
# iptables is included for up/down scripts (e.g. a kill switch).
ARG IPTABLES_VERSION=1.8.13

RUN apk add --no-cache \
        "openvpn~=${OPENVPN_VERSION}" \
        "iptables~=${IPTABLES_VERSION}"

# Relative paths in the client config (ca, cert, key, ...) resolve against /vpn
WORKDIR /vpn
VOLUME ["/vpn"]

# Healthy as soon as OpenVPN has brought up its tunnel interface: a tun/tap
# device, or a kernel DCO device (type 65534 = ARPHRD_NONE) on newer hosts
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["/bin/sh", "-c", "ls /sys/class/net/*/tun_flags >/dev/null 2>&1 || grep -qsx 65534 /sys/class/net/*/type"]

ENTRYPOINT ["openvpn"]
