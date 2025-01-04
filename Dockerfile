FROM alpine:3.21.0

ARG BUILD_RFC3339="1970-01-01T00:00:00Z"
ARG COMMIT
ARG VERSION="2.6.12-r1"

STOPSIGNAL SIGKILL

LABEL org.opencontainers.image.ref.name="frauhottelmann/openvpn-client" \
      org.opencontainers.image.created=$BUILD_RFC3339 \
      org.opencontainers.image.authors="frauhottelmann" \
      org.opencontainers.image.documentation="https://github.com/frauhottelmann/openvpn-client/blob/master/README.md" \
      org.opencontainers.image.description="OpenVPN Client in a Docker Container" \
      org.opencontainers.image.licenses="GPLv3" \
      org.opencontainers.image.source="https://github.com/frauhottelmann/openvpn-client" \
      org.opencontainers.image.revision=$COMMIT \
      org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.url="https://hub.docker.com/r/frauhottelmann/openvpn-client"

ENTRYPOINT ["openvpn"]
VOLUME ["/vpn"]

RUN apk add --no-cache openvpn=2.6.12-r1 iptables=1.8.10-r5
