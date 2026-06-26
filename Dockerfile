# syntax=docker.io/docker/dockerfile:1
ARG BASE_IMAGE="docker.io/library/ubuntu:noble-20260410"
ARG APT_UPDATE_SNAPSHOT=20260410T030400Z
ARG CARTESI_MACHINE_EMULATOR_VERSION="0.20.0"
ARG CARTESI_IMAGE_KERNEL_VERSION="0.20.0"
ARG CARTESI_LINUX_KERNEL_VERSION="6.5.13-ctsi-1-v0.20.0"
ARG CARTESI_ROLLUPS_NODE_VERSION="2.0.0-alpha.12"
ARG CARTESI_CLI_VERSION="2.0.0-alpha.35"
ARG FOUNDRY_VERSION="1.5.1"
ARG SQUASHFS_TOOLS_VERSION="bad1d213ab6df587d6fa0ef7286180fbf7b86167" # 4.7.4
ARG XGENEXT2_VERSION="1.5.6"
ARG NVM_VERSION="977563e97ddc66facf3a8e31c6cff01d236f09bd" # 0.40.3
ARG NODE_VERSION="24.14.0"
ARG ALTO_VERSION="1.2.7"
ARG ALTO_PACKAGE_VERSION="0.0.20"
ARG CARTESAPP_VERSION="1.4.0"
ARG PODMAN_VERSION=5.8.2-1

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
    amd64) echo "73640b01bd9ed29fdb4965085099371f8cf0dbbec3e2086cf54564efc4dcfe88 /tmp/foundry.tar.gz" | sha256sum --check ;;
    arm64) echo "cccf28bdf202289e837a9e21ed213b2b80dc1e806e12f1717bc98a44315c331e /tmp/foundry.tar.gz" | sha256sum --check ;;
    *) echo "unsupported architecture: ${TARGETARCH}"; exit 1 ;;
esac
tar -zx -f /tmp/foundry.tar.gz -C /usr/local/bin
EOF

################################################################################
# cartesi rollups target
FROM base AS rollups
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
    amd64) echo "46b2f37b889091df3b89a8909467935f8dd4a1426eeb0491b6a346a12f0c341c  /tmp/machine-emulator.deb" | sha256sum --check ;;
    arm64) echo "27ea10571335ad174b75388e7de54a3d3434bd607554d8c0bdf6abca47ceae0d  /tmp/machine-emulator.deb" | sha256sum --check ;;
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
#     amd64) echo "b2db03fcab1453238346fe6638b50693a405659fd73fe3ddca5be8d4e950528a /tmp/cartesi-rollups-node.deb" | sha256sum --check ;;
#     arm64) echo "e080a25f19f04b3d2164354c49989dcd72c02af6866623a70816eb08f0d75490 /tmp/cartesi-rollups-node.deb" | sha256sum --check ;;
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
# install packages
FROM rollups AS install
ARG APT_UPDATE_SNAPSHOT
ARG ALTO_VERSION
ARG ALTO_PACKAGE_VERSION
ARG CARTESI_MACHINE_EMULATOR_VERSION
ARG NODE_VERSION
ARG NVM_VERSION
ARG TARGETARCH
ARG TARGETOS
ARG XGENEXT2_VERSION
ARG CARTESAPP_VERSION
ARG PODMAN_VERSION

USER root
ARG DEBIAN_FRONTEND=noninteractive
RUN <<EOF
apt-get update --snapshot=${APT_UPDATE_SNAPSHOT}
apt-get install -y --no-install-recommends \
    git \
    jq \
    libarchive-tools \
    liblzo2-2 \
    libslirp0 \
    lua5.4 \
    locales \
    python3 \
    python3-pip \
    python3-venv \
    qemu-user-static \
    vim \
    xxd \
    xz-utils
EOF

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

ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en


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

RUN <<EOF
set -e
apt-get install -y --no-install-recommends \
    gnupg \
    uidmap \
    netavark
. /etc/os-release
echo "deb http://download.opensuse.org/repositories/home:/alvistack/xUbuntu_${VERSION_ID}/ /" \
    | tee /etc/apt/sources.list.d/home:alvistack.list
curl -fsSL https://download.opensuse.org/repositories/home:alvistack/xUbuntu_${VERSION_ID}/Release.key \
    | gpg --dearmor | tee /etc/apt/trusted.gpg.d/home_alvistack.gpg > /dev/null
apt-get update --snapshot=${APT_UPDATE_SNAPSHOT}
apt-get install -y --no-install-recommends \
    podman\
    podman-compose \
    passt
apt-get remove --purge -y \
    gnupg
rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/home:alvistack.list /etc/apt/trusted.gpg.d/home_alvistack.gpg
apt-get update --snapshot=${APT_UPDATE_SNAPSHOT}
EOF

COPY --chmod=755 <<EOF /usr/bin/docker
#!/bin/sh
set -eu

filtered=""
last_arg=""
arg_orig=""
for arg in "\$@"; do
    arg_orig="\$arg"
    if [ "\$last_arg" = "--progress" ] && [ "\$arg" = "quiet" ]; then
        filtered="\$filtered --quiet"
    fi
    if [ "\$1" =  "compose" ]; then
        if [ "\$last_arg" = "-f" ] && [ "\$arg" = "-" ]; then
            tmpfile=\$(mktemp)
            cat > "\$tmpfile"
            trap "rm -f \$tmpfile" EXIT
            arg=\$tmpfile
        fi
        if [ "\$arg" = "--project-directory" ] || [ "\$last_arg" = "--project-directory" ] || [ "\$arg" = "--format" ] || [ "\$last_arg" = "--format" ]; then
           arg=""
        fi
        filtered="\$filtered \$arg"
    else
        [ "\$arg" = "--progress" ] || [ "\$last_arg" = "--progress" ] || filtered="\$filtered \$arg"
    fi
    last_arg="\$arg_orig"
done

# shellcheck disable=SC2086
exec podman \$filtered
EOF

RUN <<EOF
set -e
echo 'ubuntu:100000:65535' > /etc/subuid
echo 'ubuntu:100000:65535' > /etc/subgid
EOF

################################################################################
# user install packages
FROM install AS user-install
USER ubuntu

RUN mkdir -p /home/ubuntu/.config/containers
COPY <<EOF /home/ubuntu/.config/containers/containers.conf
[containers]
default_sysctls = []
netns = "host"
pidns = "host"
EOF

COPY <<EOF /home/ubuntu/.config/containers/registries.conf
unqualified-search-registries = ["docker.io"]
EOF

# Install nvm and node
ENV NVM_DIR=/home/ubuntu/.nvm
RUN <<EOF
curl -o- --fail --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash
. "$NVM_DIR/nvm.sh"
nvm install $NODE_VERSION
nvm use $NODE_VERSION
nvm alias default $NODE_VERSION
EOF
ENV PATH="${NVM_DIR}/versions/node/v${NODE_VERSION}/bin:$PATH"

# Install nodejs packages
COPY --from=alto /app/alto/src/pimlico-alto-${ALTO_PACKAGE_VERSION}.tgz /tmp/pimlico-alto.tgz

RUN npm install -g /tmp/pimlico-alto.tgz

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN <<EOF
# Ensure the venv is used for subsequent RUN and at runtime
pip3 install --no-cache cartesapp[dev]@git+https://github.com/prototyp3-dev/cartesapp@v${CARTESAPP_VERSION}
EOF

RUN echo <<EOF
export NVM_DIR="\$([ -z "\${XDG_CONFIG_HOME-}" ] && printf %s "\${HOME}/.nvm" || printf %s "\${XDG_CONFIG_HOME}/nvm")"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh" # This loads nvm

export PODMAN_COMPOSE_WARNING_LOGS=false

export PATH=/home/ubuntu/.local/bin:/opt/venv/bin:\$PATH
EOF >> /home/ubuntu/.bashrc

USER root

# cleanup
RUN <<EOF
set -e
rm -rf /tmp/* /var/lib/apt/lists/* /var/log/* /var/cache/*
EOF

FROM user-install AS runtime

USER ubuntu
WORKDIR /home/ubuntu

