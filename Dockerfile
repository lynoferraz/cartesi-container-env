
# ARG BASE_IMAGE="docker.io/library/debian:bookworm-20260421-slim@sha256:5a2a80d11944804c01b8619bc967e31801ec39bf3257ab80b91070eb23625644"
ARG BASE_IMAGE="docker.io/library/ubuntu:noble-20260410@sha256:cdb5fd928fced577cfecf12c8966e830fcdf42ee481fb0b91904eeddc2fe5eff"
ARG APT_UPDATE_SNAPSHOT=20260410T030400Z
ARG CARTESI_MACHINE_EMULATOR_VERSION="0.19.0"
ARG CARTESI_IMAGE_KERNEL_VERSION="0.20.0"
ARG CARTESI_LINUX_KERNEL_VERSION="6.5.13-ctsi-1-v0.20.0"
ARG CARTESI_ROLLUPS_NODE_VERSION="2.0.0-alpha.11"
ARG CARTESI_CLI_VERSION="2.0.0-alpha.34"
ARG FOUNDRY_VERSION="1.4.3"
ARG SQUASHFS_TOOLS_VERSION="bad1d213ab6df587d6fa0ef7286180fbf7b86167" # 4.7.4
ARG XGENEXT2_VERSION="1.5.6"
ARG NVM_VERSION="977563e97ddc66facf3a8e31c6cff01d236f09bd" # 0.40.3
ARG NODE_VERSION="24.14.0"
ARG ALTO_VERSION="1.2.7"
ARG ALTO_PACKAGE_VERSION="0.0.20"
ARG CARTESAPP_VERSION="1.2.6"
ARG CLAUDEAI_VERSION=2.1.132

################################################################################
# base image
FROM ${BASE_IMAGE} AS base
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
ARG APT_UPDATE_SNAPSHOT
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
apt-get update --snapshot=${APT_UPDATE_SNAPSHOT}
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    xz-utils
EOF

################################################################################
# builder image
FROM base AS builder
WORKDIR /usr/local/src
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    build-essential \
    libarchive-dev \
    libtool \
    liblz4-dev \
    liblzma-dev \
    liblzo2-dev \
    libzstd-dev \
    zlib1g-dev
rm -rf /var/lib/apt/lists/*
EOF

################################################################################
# build msquashfs-tools
FROM builder AS squashfs-tools
ARG SQUASHFS_TOOLS_VERSION
WORKDIR /usr/local/src/squashfs-tools
ADD https://github.com/plougher/squashfs-tools.git#${SQUASHFS_TOOLS_VERSION}:squashfs-tools .
RUN <<EOF
make
./mksquashfs -version
EOF

################################################################################
# foundry installer
FROM base AS foundry
ARG FOUNDRY_VERSION
ARG TARGETARCH
ARG TARGETOS
RUN <<EOF
mkdir -p /usr/local/bin
curl -fsSL https://github.com/foundry-rs/foundry/releases/download/v${FOUNDRY_VERSION}/foundry_v${FOUNDRY_VERSION}_${TARGETOS}_${TARGETARCH}.tar.gz \
  -o /tmp/foundry.tar.gz
case "${TARGETARCH}" in
    amd64) echo "325ba04dc5cb41c110723b00ac291f8269f8cd785028299aad8252ef980961a7 /tmp/foundry.tar.gz" | sha256sum --check ;;
    arm64) echo "209492cb4ebd723d9eac002fa30f41f53c8810105b67d3c32fe8201cf70f89d4 /tmp/foundry.tar.gz" | sha256sum --check ;;
    *) echo "unsupported architecture: ${TARGETARCH}"; exit 1 ;;
esac
tar -zx -f /tmp/foundry.tar.gz -C /usr/local/bin
EOF

################################################################################
# cartesi rollups-runtime target
FROM base AS rollups-runtime
ARG CARTESI_MACHINE_EMULATOR_VERSION
# ARG CARTESI_ROLLUPS_NODE_VERSION
ARG TARGETARCH

USER root
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
apt-get install -y --no-install-recommends \
    libslirp0 \
    lua5.4
rm -rf /var/lib/apt/lists/*
EOF

# Install cartesi-machine emulator
RUN <<EOF
curl -fsSL https://github.com/cartesi/machine-emulator/releases/download/v${CARTESI_MACHINE_EMULATOR_VERSION}/machine-emulator_${TARGETARCH}.deb \
    -o /tmp/machine-emulator.deb
case "${TARGETARCH}" in
    amd64) echo "adae6b030a8990e316997aad53d175192bfeaa84ad12ee19491366377073572b  /tmp/machine-emulator.deb" | sha256sum --check ;;
    arm64) echo "15ebb64d8cd3296564d2297dd809d1d72c13a938976bb4ecc5e5c82e71bb8069  /tmp/machine-emulator.deb" | sha256sum --check ;;
    *) echo "unsupported architecture: ${TARGETARCH}"; exit 1 ;;
esac
apt-get install -y --no-install-recommends /tmp/machine-emulator.deb
rm /tmp/machine-emulator.deb
cartesi-machine --version-json
EOF

# # Install cartesi-rollups-node
# RUN <<EOF
# curl -fsSL https://github.com/cartesi/rollups-node/releases/download/v${CARTESI_ROLLUPS_NODE_VERSION}/cartesi-rollups-node-v${CARTESI_ROLLUPS_NODE_VERSION}_${TARGETARCH}.deb \
#     -o /tmp/cartesi-rollups-node.deb
# case "${TARGETARCH}" in
#     amd64) echo "72a7db2aabbf0e8d58849c9546f7c180f68c9d0550606d536d42882603550fb4 /tmp/cartesi-rollups-node.deb" | sha256sum --check ;;
#     arm64) echo "b50b445355dda23ee06f08e7d28ed8452025e59934310c7a8115531af6eeae0c /tmp/cartesi-rollups-node.deb" | sha256sum --check ;;
#     *) echo "unsupported architecture: ${TARGETARCH}"; exit 1 ;;
# esac
# apt-get install -y --no-install-recommends /tmp/cartesi-rollups-node.deb
# rm /tmp/cartesi-rollups-node.deb
# mkdir -p /var/lib/cartesi-rollups-node/snapshots
# chmod 755 /var/lib/cartesi-rollups-node/snapshots
# chown cartesi:cartesi /var/lib/cartesi-rollups-node/snapshots
# cartesi-rollups-node --version
# EOF

################################################################################
# alto build
FROM node:${NODE_VERSION} AS alto
ARG ALTO_VERSION
ARG NODE_VERSION
ARG TARGETARCH
ARG TARGETOS

# install foundry, necessary for building alto
COPY --from=foundry /usr/local/bin/forge /usr/local/bin/forge

WORKDIR /app

RUN <<EOF
set -eu
npm install -g pnpm
git clone --branch v${ALTO_VERSION} --depth 1 --recurse-submodules https://github.com/pimlicolabs/alto.git
cd alto
pnpm install
pnpm run build:contracts
pnpm run build
cd src && pnpm pack # produces pimlico-alto-${ALTO_PACKAGE_VERSION}.tgz
EOF

################################################################################
# cartesi rollups-runtime target
FROM base AS cartesi-cli
ARG CARTESI_CLI_VERSION
# ARG CARTESI_ROLLUPS_NODE_VERSION
ARG TARGETARCH
ARG TARGETOS

USER root

# Install cartesi-machine emulator
RUN <<EOF
case "${TARGETARCH}" in
    amd64) 
    curl -fsSL https://github.com/cartesi/cli/releases/download/%40cartesi%2Fcli%40${CARTESI_CLI_VERSION}/cartesi-${TARGETOS}-x64.tar.gz \
        -o /tmp/cartesi-cli.tar.gz
    # echo "adae6b030a8990e316997aad53d175192bfeaa84ad12ee19491366377073572b  /tmp/machine-emulator.deb" | sha256sum --check 
    ;;
    arm64)
    curl -fsSL https://github.com/cartesi/cli/releases/download/%40cartesi%2Fcli%40${CARTESI_CLI_VERSION}/cartesi-${TARGETOS}-arm64.tar.gz \
        -o /tmp/cartesi-cli.tar.gz
    ;;
    *) echo "unsupported architecture: ${TARGETARCH}"; exit 1 ;;
esac
tar -zx -f /tmp/cartesi-cli.tar.gz -C /usr/local/bin
mv /usr/local/bin/cartesi-${TARGETOS}-* /usr/local/bin/cartesi
rm /tmp/cartesi-cli.tar.gz
EOF

################################################################################
# linux kernel image stage
FROM scratch AS kernel-image
ARG CARTESI_IMAGE_KERNEL_VERSION
ARG CARTESI_LINUX_KERNEL_VERSION

ADD --checksum=sha256:65dd100ff6204346ac2f50f772721358b5c1451450ceb39a154542ee27b4c947 \
    https://github.com/cartesi/image-kernel/releases/download/v${CARTESI_IMAGE_KERNEL_VERSION}/linux-${CARTESI_LINUX_KERNEL_VERSION}.bin \
    /usr/share/cartesi-machine/images/linux.bin

################################################################################
# linux headers stage
FROM base AS kernel-headers
ARG CARTESI_IMAGE_KERNEL_VERSION
ARG CARTESI_LINUX_KERNEL_VERSION

ADD --checksum=sha256:4a4714bfa8c0028cb443db2036fad4f8da07065c1cb4ac8e0921a259fddd731b \
    https://github.com/cartesi/image-kernel/releases/download/v${CARTESI_IMAGE_KERNEL_VERSION}/linux-headers-${CARTESI_LINUX_KERNEL_VERSION}.tar.xz \
    /tmp/linux-headers-${CARTESI_LINUX_KERNEL_VERSION}.tar.xz
RUN tar -xJf "/tmp/linux-headers-${CARTESI_LINUX_KERNEL_VERSION}.tar.xz" -C /

################################################################################
# sdk final image
FROM rollups-runtime AS runtime
ARG APT_UPDATE_SNAPSHOT
ARG ALTO_VERSION
ARG ALTO_PACKAGE_VERSION
ARG CARTESI_MACHINE_EMULATOR_VERSION
ARG NODE_VERSION
ARG NVM_VERSION
ARG TARGETARCH
ARG XGENEXT2_VERSION
ARG CARTESAPP_VERSION
ARG CLAUDEAI_VERSION

USER root
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
apt-get update --snapshot=${APT_UPDATE_SNAPSHOT}
apt-get install -y --no-install-recommends \
    python3 \
    python3-venv \
    python3-pip \
    git \
    jq \
    libarchive-tools \
    liblzo2-2 \
    libslirp0 \
    lua5.4 \
    locales \
    vim \
    xxd \
    xz-utils
rm -rf /var/lib/apt/lists/*
EOF

# Install nvm and node
ENV NVM_DIR=/root/.nvm
RUN <<EOF
curl -o- --fail --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash
. "$NVM_DIR/nvm.sh"
nvm install $NODE_VERSION
nvm use $NODE_VERSION
nvm alias default $NODE_VERSION
EOF
ENV PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/bin:$PATH"

# Install dpkg release of xgenext2fs
RUN <<EOF
curl -fsSL https://github.com/cartesi/genext2fs/releases/download/v${XGENEXT2_VERSION}/xgenext2fs_${TARGETARCH}.deb \
    -o /tmp/xgenext2fs.deb
dpkg -i /tmp/xgenext2fs.deb
rm /tmp/xgenext2fs.deb
xgenext2fs --version
sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8
EOF

# Install nodejs packages
COPY --from=alto /app/alto/src/pimlico-alto-${ALTO_PACKAGE_VERSION}.tgz /tmp/pimlico-alto.tgz
RUN <<EOF
npm install -g \
    /tmp/pimlico-alto.tgz

rm /tmp/pimlico-alto.tgz
EOF

ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en

# healthcheck script using net_listening JSON-RPC method
# COPY alto /usr/local/bin
# COPY devnet /usr/local/bin
# COPY eth_isready /usr/local/bin

# COPY entrypoint.sh /usr/local/bin/
COPY --from=foundry /usr/local/bin/anvil /usr/local/bin/
COPY --from=foundry /usr/local/bin/cast /usr/local/bin/
COPY --from=squashfs-tools /usr/local/src/squashfs-tools/mksquashfs /usr/local/bin/
COPY --from=kernel-image --chmod=644 /usr/share/cartesi-machine/images/linux.bin /usr/share/cartesi-machine/images/linux.bin
COPY --from=kernel-headers /include/linux /include/linux
COPY --from=cartesi-cli /usr/local/bin/cartesi /usr/local/bin/

RUN <<EOF
mkdir -p /opt
chmod 777 /opt
mkdir -p /projects
chown ubuntu:ubuntu /projects
EOF


RUN <<EOFOUT
set -e
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update --snapshot=${APT_UPDATE_SNAPSHOT}
apt-get install -y --no-install-recommends \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    kmod \
    uidmap \
    libcap2-bin
# rm -rf /var/lib/apt/lists/*
EOFOUT

# RUN set -eux; \
# 	echo 'ubuntu:100000:65536' >> /etc/subuid; \
# 	echo 'ubuntu:100000:65536' >> /etc/subgid

# COPY --chmod=755 <<EOF /usr/local/sbin/docker
# #!/bin/sh
# if ! (pgrep dockerd >/dev/null 2>&1); then
#     dockerd > ~/.dockerd.log 2>&1 &
# fi
# exec /usr/sbin/docker "\$@"
# EOF


RUN <<EOF
set -e
chmod 0755 /usr/bin/newuidmap /usr/bin/newgidmap
setcap cap_setuid+ep /usr/bin/newuidmap
setcap cap_setgid+ep /usr/bin/newgidmap
chmod -s /usr/bin/newuidmap
chmod -s /usr/bin/newgidmap
EOF

FROM runtime AS user-runtime
USER ubuntu

RUN <<EOF
set -e
curl -fsSL https://get.docker.com/rootless > /tmp/rootless.sh
chmod +x /tmp/rootless.sh
/tmp/rootless.sh --force
rm /tmp/rootless.sh

EOF

ENV PATH=/home/ubuntu/bin:$PATH
RUN echo "export XDG_RUNTIME_DIR=/home/ubuntu/.docker/run" >> /home/ubuntu/.bashrc
RUN echo "export DOCKER_HOST=unix:///home/ubuntu/.docker/run/docker.sock" >> /home/ubuntu/.bashrc

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN <<EOF
# Ensure the venv is used for subsequent RUN and at runtime
pip3 install --no-cache cartesapp[dev]@git+https://github.com/prototyp3-dev/cartesapp@v${CARTESAPP_VERSION}
EOF

RUN curl -fsSL https://claude.ai/install.sh | bash -s ${CLAUDEAI_VERSION}

ENV PATH="/home/ubuntu/.local/bin:$PATH"


