FROM alpine:3

ARG BUILD_RFC3339="1970-01-01T00:00:00Z"
ARG COMMIT
ARG VERSION="2.7.5-r0"

STOPSIGNAL SIGKILL

ENTRYPOINT ["openvpn"]
VOLUME ["/vpn"]

RUN apk add --no-cache openvpn=2.7.5-r0 iptables=1.8.13-r0
