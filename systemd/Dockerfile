ARG TAG=0.0.0-devxp

ARG BUILDER_CACHE_BUSTER=0
ARG UBUNTU_VERSION=noble # 24.04 (mantic - 23.10)

FROM golang:bookworm AS builder

ARG BRANCH
ARG BUILDER_CACHE_BUSTER

RUN <<EOF
    apt-get update
    apt-get install -y git bash
EOF

SHELL [ "/usr/bin/env", "-S", "bash", "-ex", "-o", "pipefail", "-c" ]
ENV PS4="+ "

RUN <<EOF
    : cache buster ${BUILDER_CACHE_BUSTER}
    go install github.com/go-delve/delve/cmd/dlv@latest
    go install github.com/LouisBrunner/avahi2dns@latest
    go install github.com/cespare/reflex@latest

    GOPROXY=direct go install github.com/nxmatic/go-docker2mdns@latest
EOF

FROM debian:bookworm-slim AS debian

RUN <<EOF
    apt-get -y update
    apt-get -y install bash rsync
EOF

SHELL [ "/usr/bin/env", "-S", "bash", "-ex", "-o", "pipefail", "-c" ]
ENV PS4="+ "

FROM debian AS avahi2dns

ARG TAG

COPY --chmod=755 --from=builder /go/bin/avahi2dns /usr/local/bin/

VOLUME [ "/var/run/dbus", "/var/run/avahi-daemon" ]

CMD [ "/usr/local/bin/avahi2dns" ]

RUN <<EOF
    : define registries shortname for the image to be installed in the VM
    mkdir -p /.templates/etc/containers/registries.conf.d/
    cat <<!  | cut -c 5- | tee /.templates/etc/containers/registries.conf.d/avahi2dns.conf
    [[registry]]
    prefix = "avahi2dns"
    location = "host.containers.internal:5000/docker-avahi2dns"
!

    : define registries quadlet to be installed in the VM
    mkdir -p /.templates/etc/containers/systemd/
    cat <<! | cut -c 5- | tee /.templates/etc/containers/systemd/avahi2dns.container
    [Container]
    Image=docker-avahi2dns:${TAG}
    ContainerName=avahi2dns
    Network=host
    PodmanArgs=--security-opt apparmor=unconfined
    Volume=/var/run/dbus:/var/run/dbus
    Volume=/var/run/avahi-daemon:/var/run/avahi-daemon

    [Service]
    Restart=always

    [Install]
    WantedBy=multi-user.target
!
EOF

FROM debian AS docker2mdns

ARG TAG

RUN <<EOF
    apt-get -y update
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
      gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    cat <<! | cut -c 5- | tee /etc/apt/sources.list.d/docker-ce.sources
    Types: deb
    Architectures: $(dpkg --print-architecture)
    Signed-By: /usr/share/keyrings/docker-archive-keyring.gpg
    URIs: https://download.docker.com/linux/debian
    Suites: $(lsb_release -cs)
    Components: stable
!
    apt-get -y update
    apt-get -y install docker-ce-cli
EOF

ENV DOCKER_HOST="tcp://host.lima.internal:2375"

COPY --chmod=755 --from=builder /go/bin/go-docker2mdns /usr/local/bin/docker2mdns

CMD [ "/usr/local/bin/docker2mdns" ]

RUN <<EOF
    : define registries shortname for the image to be installed in the VM
    mkdir -p /.templates/etc/containers/registries.conf.d/
    cat <<!  | cut -c 5- | tee -a /.templates/etc/containers/registries.conf.d/docker2mdns.conf
    [[registry]]
    prefix = "docker2mdns"
    location = "host.containers.internal:5000/docker-docker2mdns"
!
    : define registries quadlet to be installed in the VM
    mkdir -p /.templates/etc/containers/systemd/
    cat <<! | cut -c 4- | tee -a /.templates/etc/containers/systemd/docker2mdns.container
    [Container]
    Image=containers.internal/docker-docker2mdns-debug:${TAG}
    ContainerName=docker2mdns
    Network=host
    PublishPort=0000:2345
    Volume=/var/run/dbus:/var/run/dbus
    Volume=/var/run/avahi-daemon:/var/run/avahi-daemon

    [Service]
    Restart=always

    [Install]
    WantedBy=multi-user.target
!
EOF

FROM docker2mdns AS docker2mdns-debug

EXPOSE 2345

COPY --chmod=755 --from=builder /go/bin/dlv /usr/local/bin/
COPY --chmod=755 --from=builder /go/bin/reflex /usr/local/bin/

RUN <<'EOF'
    mkdir -p ~/.config
    cat <<'!'' | cut -c 5- | tee ~/.config/reflex.conf
    -r .go$ -s -- sh -c "dlv debug ~/config/reflex.conf --headless --listen=:2345 --api-version=2 --log"
!
EOF

ENTRYPOINT ["reflex", "-c", "/etc/reflex/reflex.conf"]

# Use the official BuildKit image as the base
FROM moby/buildkit:latest AS buildkit

RUN <<!
    apk add --no-cache coreutils bash patch
    apk add --no-cache dbus
!

SHELL [ "/usr/bin/env", "-S", "bash", "-ex", "-o", "pipefail", "-c" ]
ENV PS4="+ "

# Copy a custom Avahi configuration file if needed
#COPY avahi-daemon.conf /etc/avahi/avahi-daemon.conf

# COPY --chmod=644 <<'nsswitch.conf' <<'mdns.allow' /etc/
# hosts:          files mdns4_minimal [NOTFOUND=return] dns mdns4
# nsswitch.conf
# # disable the two heuristics (https://github.com/avahi/nss-mdns#etcmdnsallow)
# .local.
# .local
# mdns.allow

COPY --chmod=755 --from=builder /go/bin/avahi2dns /usr/local/bin/avahi2dns

COPY --chmod=644 <<'resolv.conf' /etc/
nameserver 127.0.0.1
nameserver 127.0.0.53
options edns0 trust-ad
resolv.conf

COPY --chmod=755 <<'docker-entrypoint.sh' /usr/local/sbin/
#!/usr/bin/env -S bash -e -o pipefail

# Start dbus daemon
mkdir -p /var/run/dbus
dbus-daemon --system

# Start avahi2dns
/usr/local/bin/avahi2dns --debug &

# Execute the original BuildKit entrypoint
exec buildkitd "$@"
docker-entrypoint.sh

ENTRYPOINT ["/usr/local/sbin/docker-entrypoint.sh"]

FROM debian AS novnc

SHELL [ "/usr/bin/env", "-S", "bash", "-ex", "-o", "pipefail", "-c" ]

RUN <<EOF
    : Install git, supervisor, VNC, X11 packages
    apt-get update
    apt-get install -y \
      bash \
      curl \
      iproute2 \
      jq \
      fluxbox \
      git \
      net-tools \
      novnc \
      supervisor \
      x11vnc \
      xterm \
      xvfb
EOF

ENV \
    HOME=/app \
    DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    LC_ALL=C.UTF-8 \
    DISPLAY=:0.0 \
    DISPLAY_WIDTH=1024 \
    DISPLAY_HEIGHT=768 \
    RUN_XTERM=yes \
    RUN_FLUXBOX=yes

ARG VNCUSER=vncuser

RUN <<EOF
    : add ${VNCUSER} user
    useradd -U -r -m -d ${HOME} -s /usr/bin/bash ${VNCUSER}
EOF

USER ${VNCUSER}

VOLUME ${HOME}

COPY novnc/ ${HOME}/

EXPOSE 8080/tcp
EXPOSE 5900/tcp
EXPOSE 6000/tcp

CMD ["/app/entrypoint.sh"]

WORKDIR /app/

FROM novnc AS wine

USER root

RUN <<EOF
    RELEASE_URL=https://api.github.com/repos/AndreRH/hangover/releases
    ASSET_SELECTOR='.assets[] | select(.name | contains("debian12_bookworm_arm64")) | .browser_download_url'
    ASSET_URL="$( curl -L -s "${RELEASE_URL}/latest" |
                 jq -r "${ASSET_SELECTOR}" )"
    curl -L -s -o /dev/stdout  "${ASSET_URL}" |
      tar --wildcards -s -C /tmp -xf - '*wine*.deb'
      apt-get -y install /tmp/hangover-wine_*.deb
      rm -f /tmp/hangover-wine_*.deb
EOF

USER ${VNCUSER}

FROM novnc AS zen

USER root

RUN <<EOF
    apt-get -y install flatpak
    apt-get -y install gnome-software-plugin-flatpak
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
EOF

USER ${VNCUSER}
