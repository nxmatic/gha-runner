FROM debian:bookworm-slim AS keys-builder

WORKDIR /keys

RUN <<!
    apt-get -y install openssh-client
    ssh-keygen -t ed25519 -N "" -f builder_ed25519_key
!

FROM nixos/nix:latest

USER builder

COPY --chmod=444 --from=keys-builder /keys/ /var/ssh/keys

RUN <<!
  nix profile install github:nxmatic/nix-linux-builder
!

VOLUME [ "/var/ssh-keys" ]

