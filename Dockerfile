# syntax=docker.io/docker/dockerfile:1
ARG BASE_IMAGE="docker.io/library/ubuntu:noble-20260917"
ARG APT_UPDATE_SNAPSHOT=20260410T030400Z
ARG CARTESI_MACHINE_EMULATOR_VERSION="0.21.0"
ARG CARTESI_IMAGE_KERNEL_VERSION="0.21.0"
ARG CARTESI_LINUX_KERNEL_VERSION="6.5.13-ctsi-2-v0.21.0"
ARG CARTESI_ROLLUPS_NODE_VERSION="2.0.0-alpha.13"
ARG CARTESI_CLI_VERSION="2.0.0-alpha.37"
ARG FOUNDRY_VERSION="1.5.1"
ARG SQUASHFS_TOOLS_VERSION="bad1d213ab6df587d6fa0ef7286180fbf7b86167" # 4.7.4
ARG XGENEXT2_VERSION="1.5.6"
ARG NVM_VERSION="977563e97ddc66facf3a8e31c6cff01d236f09bd" # 0.40.3
ARG NODE_VERSION="24.21.0"
ARG ALTO_VERSION="1.2.7"
ARG ALTO_PACKAGE_VERSION="0.0.20"
ARG CARTESAPP_VERSION="1.4.1"
ARG PODMAN_VERSION=6.1.2
ARG PODMAN_COMPOSE_VERSION=1.6.0

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
    libgomp1 \
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
    lua5.4 \
    lua-lpeg
rm -rf /var/lib/apt/lists/*
EOF

# Install cartesi-machine emulator
RUN <<EOF
curl -fsSL https://github.com/cartesi/machine-emulator/releases/download/v${CARTESI_MACHINE_EMULATOR_VERSION}/machine-emulator_${TARGETARCH}.deb \
    -o /tmp/machine-emulator.deb
case "${TARGETARCH}" in
    amd64) echo "5f13034f43454c340062c677146daabe77c587cee1bd60342c95b8ad8f1463a3  /tmp/machine-emulator.deb" | sha256sum --check ;;
    arm64) echo "866f0bde2db53b9b8e6a6eac85e5ad4116338379fa25cdfcc5e4bf835f948bb1  /tmp/machine-emulator.deb" | sha256sum --check ;;
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

# Install cartesi cli
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

ADD --checksum=sha256:5c900060da2db2bfa84cd39cd9cd722988c83c42225f3cac55f2d3157e48f32f \
    https://github.com/cartesi/machine-linux-image/releases/download/v${CARTESI_IMAGE_KERNEL_VERSION}/linux-${CARTESI_LINUX_KERNEL_VERSION}.bin \
    /usr/share/cartesi-machine/images/linux.bin

################################################################################
# linux headers stage
FROM base AS kernel-headers
ARG CARTESI_IMAGE_KERNEL_VERSION
ARG CARTESI_LINUX_KERNEL_VERSION

ADD --checksum=sha256:e3f140a8632fcfb18218e7aea32a7d002124d3dce5ba8121ae061ab7f40a6cf4 \
    https://github.com/cartesi/machine-linux-image/releases/download/v${CARTESI_IMAGE_KERNEL_VERSION}/linux-headers-${CARTESI_LINUX_KERNEL_VERSION}.tar.xz \
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
    podman \
    passt
apt-get remove --purge -y \
    gnupg
rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/home:alvistack.list /etc/apt/trusted.gpg.d/home_alvistack.gpg
apt-get update --snapshot=${APT_UPDATE_SNAPSHOT}
EOF

# docker -> podman shim: forwards to podman / podman-compose and papers over the
# differences the cartesi CLI depends on (see the header comment inside).
COPY --chmod=755 <<'EOF' /usr/bin/docker
#!/bin/bash
# docker -> podman compatibility shim for the cartesi-sandbox rootfs.
#
# The cartesi CLI (and other tools) call `docker ...`. This shim forwards to
# podman / podman-compose while preserving argument quoting exactly, and papers
# over the differences the cartesi CLI depends on:
#   * `docker version --format '{{json .Client.Version}}'` and
#     `docker compose version --short` answer with versions that pass the CLI's
#     semver minimums (Docker >= 25.0.0, Compose >= 2.24.0).
#   * `--progress <mode>` is dropped for builds (`quiet` becomes `--quiet`).
#   * compose: a file given as `-f -` (stdin) is stored in the project directory
#     so relative paths in it resolve, and it is remembered per project name so
#     later `compose --project-name X ps|exec|port|down` calls work without -f.
#   * compose: `ps <service> --format json` is answered from `podman inspect`
#     in docker-compose's JSON shape ({"Service","State","Health"}).
#   * compose: top-level `configs` (ignored by podman-compose) are rewritten into
#     bind-mounted files by docker-shim-compose-fixup; `port` output gets the
#     0.0.0.0: prefix docker prints; `config --format` is dropped.
#   * compose up: starts podman-healthcheck-runner (no systemd in the sandbox).
# Set DOCKER_SHIM_DEBUG=1 to log the exact podman argv to stderr.
set -euo pipefail

debug() { [ -n "${DOCKER_SHIM_DEBUG:-}" ] && printf 'docker-shim: %s\n' "$*" >&2; return 0; }
run_podman() { debug "podman $(printf '%q ' "$@")"; exec podman "$@"; }

runtime_dir="${XDG_RUNTIME_DIR:-/tmp/docker-shim-$(id -u)}"
index_dir="$runtime_dir/docker-shim/projects"

sub="${1:-}"

# ---------------------------------------------------------------- version
if [ "$sub" = "version" ]; then
    if [ "${2:-}" = "--format" ] && [[ "${3:-}" == *Client.Version* ]]; then
        pv=$(podman version --format '{{.Client.Version}}' 2>/dev/null || echo unknown)
        printf '"25.0.0-podman%s"\n' "$pv"
        exit 0
    fi
    run_podman "$@"
fi

# ---------------------------------------------------------------- buildx ls
# cartesi doctor: `docker buildx ls --format '{{.Platforms}}'` must list linux/riscv64.
# podman has no `buildx ls`; report the native platform plus riscv64 when the
# qemu user-mode emulator is installed (binfmt registration lives on the host).
if [ "$sub" = "buildx" ] && [ "${2:-}" = "ls" ]; then
    case "$(uname -m)" in
        x86_64)  native="linux/amd64" ;;
        aarch64) native="linux/arm64" ;;
        *)       native="linux/$(uname -m)" ;;
    esac
    platforms="$native"
    if [ -x /usr/bin/qemu-riscv64-static ] || [ -e /proc/sys/fs/binfmt_misc/qemu-riscv64 ]; then
        platforms="$platforms,linux/riscv64"
    fi
    echo "$platforms"
    exit 0
fi

# ---------------------------------------------------------------- build
if [ "$sub" != "compose" ]; then
    args=()
    i=1
    while [ $i -le $# ]; do
        arg="${!i}"
        next_i=$((i + 1))
        next="${!next_i:-}"
        case "$arg" in
            --progress)
                [ "$next" = "quiet" ] && args+=("--quiet")
                i=$((i + 2)); continue ;;
            --progress=*)
                [ "${arg#--progress=}" = "quiet" ] && args+=("--quiet")
                i=$((i + 1)); continue ;;
        esac
        args+=("$arg")
        i=$((i + 1))
    done
    run_podman "${args[@]}"
fi

# ---------------------------------------------------------------- compose
shift   # drop "compose"

global=()
files=()
project=""
projdir=""
cmd=""
cmdargs=()
while [ $# -gt 0 ]; do
    case "$1" in
        -f|--file)               files+=("${2:?}"); shift 2 ;;
        --file=*)                files+=("${1#--file=}"); shift ;;
        -p|--project-name)       project="${2:?}"; shift 2 ;;
        --project-name=*)        project="${1#--project-name=}"; shift ;;
        --project-directory)     projdir="${2:?}"; shift 2 ;;
        --project-directory=*)   projdir="${1#--project-directory=}"; shift ;;
        --env-file|--profile)    global+=("$1" "${2:?}"); shift 2 ;;
        --env-file=*|--profile=*) global+=("$1"); shift ;;
        --ansi|--progress)       shift 2 ;;      # not supported by podman-compose
        --ansi=*|--progress=*|--compatibility) shift ;;
        -*)                      global+=("$1"); shift ;;
        *)                       cmd="$1"; shift; cmdargs=("$@"); break ;;
    esac
done

if [ "$cmd" = "version" ]; then
    cv=$(podman-compose version --short 2>/dev/null | tail -n1 || true)
    echo "2.24.0-podman-compose${cv:-unknown}"
    exit 0
fi

normalize_project() {   # docker-compose project name rules
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '_' | sed -e 's/^[^a-z0-9]*//'
}

# A compose file on stdin: store it in the project directory (relative paths in
# it resolve against the file's directory) and remember it for this project.
resolved=()
for f in "${files[@]}"; do
    if [ "$f" != "-" ]; then resolved+=("$f"); continue; fi
    tmp=$(mktemp)
    cat > "$tmp"
    name="$project"
    if [ -z "$name" ]; then
        name=$(sed -n -E 's/^name:[[:space:]]*["'"'"']?([^"'"'"'[:space:]#]+).*/\1/p' "$tmp" | head -n1)
    fi
    dir="${projdir:-$PWD}"
    dir=$(cd "$dir" && pwd)
    [ -n "$name" ] || name=$(basename "$dir")
    name=$(normalize_project "$name")
    [ -n "$project" ] || project="$name"
    dest="$dir/.docker-shim.$name.compose.yml"
    mv "$tmp" "$dest"
    chmod 600 "$dest"
    mkdir -p "$index_dir"
    printf '%s\n' "$dest" > "$index_dir/$name"
    debug "stored stdin compose file for project '$name' at $dest"
    # podman-compose ignores compose `configs`; turn them into bind-mounted files.
    if command -v docker-shim-compose-fixup >/dev/null 2>&1; then
        docker-shim-compose-fixup "$dest" "$name" || debug "compose fixup failed for $dest"
    fi
    resolved+=("$dest")
done
files=("${resolved[@]}")

# No -f given: reuse the file remembered for this project name, if any.
if [ ${#files[@]} -eq 0 ] && [ -n "$project" ]; then
    key=$(normalize_project "$project")
    if [ -f "$index_dir/$key" ]; then
        cached=$(cat "$index_dir/$key")
        if [ -f "$cached" ]; then
            files+=("$cached")
            debug "using remembered compose file $cached"
        fi
    fi
fi

pc=()
for f in "${files[@]}"; do pc+=("-f" "$f"); done
[ -n "$project" ] && pc+=("--project-name" "$project")
pc+=("${global[@]}")

case "$cmd" in
    ps)
        # `compose ps <service> --format json` -> one JSON object for that service.
        services=()
        rest=()
        want_json=0
        j=0
        while [ $j -lt ${#cmdargs[@]} ]; do
            a="${cmdargs[$j]}"
            case "$a" in
                --format)       [ "${cmdargs[$((j+1))]:-}" = "json" ] && want_json=1; rest+=("$a" "${cmdargs[$((j+1))]:-}"); j=$((j+2)); continue ;;
                --format=json)  want_json=1; rest+=("$a"); j=$((j+1)); continue ;;
                -*)             rest+=("$a") ;;
                *)              services+=("$a") ;;
            esac
            j=$((j+1))
        done
        if [ ${#services[@]} -eq 1 ]; then
            svc="${services[0]}"
            name="${project:-$(normalize_project "$(basename "$PWD")")}"
            ctr="${name}_${svc}_1"
            if podman container exists "$ctr" 2>/dev/null; then
                podman inspect --format \
                    '{"Service":"'"$svc"'","Name":"{{.Name}}","State":"{{.State.Status}}","Health":"{{if .State.Health}}{{.State.Health.Status}}{{end}}","ExitCode":{{.State.ExitCode}}}' \
                    "$ctr"
            fi
            exit 0
        fi
        run_podman compose "${pc[@]}" ps "${rest[@]}"
        ;;
    up)
        podman-healthcheck-runner start >/dev/null 2>&1 || true
        run_podman compose "${pc[@]}" up "${cmdargs[@]}"
        ;;
    down)
        debug "podman compose $(printf '%q ' "${pc[@]}") down $(printf '%q ' "${cmdargs[@]}")"
        podman compose "${pc[@]}" down "${cmdargs[@]}"
        rc=$?
        if [ $rc -eq 0 ] && [ -n "$project" ]; then
            key=$(normalize_project "$project")
            if [ -f "$index_dir/$key" ]; then
                cached=$(cat "$index_dir/$key")
                case "$(basename "$cached")" in
                    .docker-shim.*.compose.yml)
                        rm -f "$cached"
                        rm -rf "$(dirname "$cached")/.docker-shim.$key.configs" ;;
                esac
                rm -f "$index_dir/$key"
            fi
        fi
        exit $rc
        ;;
    port)
        # docker prints "0.0.0.0:PORT"; podman-compose prints only "PORT" and the
        # cartesi CLI builds URLs from it.
        out=$(podman compose "${pc[@]}" port "${cmdargs[@]}") || exit $?
        case "$out" in
            ''|*:*) printf '%s\n' "$out" ;;
            *)      printf '0.0.0.0:%s\n' "$out" ;;
        esac
        ;;
    config)
        # podman-compose config has no --format; it always prints yaml.
        rest=()
        skip=0
        for a in "${cmdargs[@]}"; do
            if [ $skip = 1 ]; then skip=0; continue; fi
            case "$a" in --format) skip=1; continue ;; --format=*) continue ;; esac
            rest+=("$a")
        done
        run_podman compose "${pc[@]}" config "${rest[@]}"
        ;;
    "")
        run_podman compose "${pc[@]}"
        ;;
    *)
        run_podman compose "${pc[@]}" "$cmd" "${cmdargs[@]}"
        ;;
esac
EOF

# Runs container healthchecks on a timer (no systemd inside the sandbox).
COPY --chmod=755 <<'EOF' /usr/local/bin/podman-healthcheck-runner
#!/bin/bash
# podman-healthcheck-runner: run container healthchecks on a timer.
#
# Rootless podman schedules healthchecks through systemd transient timers.
# There is no systemd inside the sandbox, so Health.Status would stay
# "starting" forever and `depends_on: condition: service_healthy` (used by
# `cartesi run`) would never resolve. This daemon polls running containers
# that define a healthcheck and runs `podman healthcheck run` for them.
#
# Usage: podman-healthcheck-runner start   # idempotent, daemonizes
#        podman-healthcheck-runner run     # foreground loop
#        podman-healthcheck-runner stop
set -u

runtime_dir="${XDG_RUNTIME_DIR:-/tmp/docker-shim-$(id -u)}"
state_dir="$runtime_dir/docker-shim"
pidfile="$state_dir/healthcheck-runner.pid"
interval="${PODMAN_HEALTHCHECK_INTERVAL:-2}"
idle_limit="${PODMAN_HEALTHCHECK_IDLE_EXIT:-600}"   # seconds without running containers before exiting

alive() {
    local pid
    pid=$(cat "$pidfile" 2>/dev/null) || return 1
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null \
        && grep -q podman-healthcheck-runner "/proc/$pid/cmdline" 2>/dev/null
}

run_loop() {
    mkdir -p "$state_dir"
    echo $$ > "$pidfile"
    trap 'rm -f "$pidfile"; exit 0' TERM INT
    local idle=0 ids id has_hc
    while :; do
        ids=$(podman ps --filter status=running --format '{{.ID}}' 2>/dev/null) || ids=""
        if [ -z "$ids" ]; then
            idle=$((idle + interval))
            # keep going while a compose up is still in progress (image pulls can take minutes)
            if [ "$idle" -ge "$idle_limit" ] && ! pgrep -f "podman-compose .* up" >/dev/null 2>&1; then break; fi
            sleep "$interval"
            continue
        fi
        idle=0
        for id in $ids; do
            has_hc=$(podman inspect --format '{{if .Config.Healthcheck}}{{if .Config.Healthcheck.Test}}{{index .Config.Healthcheck.Test 0}}{{end}}{{end}}' "$id" 2>/dev/null) || has_hc=""
            case "$has_hc" in
                ""|NONE) continue ;;
            esac
            podman healthcheck run "$id" >/dev/null 2>&1 || true
        done
        sleep "$interval"
    done
    rm -f "$pidfile"
}

case "${1:-start}" in
    start)
        mkdir -p "$state_dir"
        alive && exit 0
        setsid nohup "$0" run >/dev/null 2>&1 < /dev/null &
        # give the daemon a moment to write its pidfile so `start` is reliably idempotent
        for _ in 1 2 3 4 5 6 7 8 9 10; do alive && exit 0; sleep 0.1; done
        exit 0
        ;;
    run)
        alive && [ "$(cat "$pidfile")" != "$$" ] && exit 0
        run_loop
        ;;
    stop)
        if alive; then kill "$(cat "$pidfile")"; fi
        rm -f "$pidfile"
        ;;
    status)
        if alive; then echo "running (pid $(cat "$pidfile"))"; else echo "not running"; exit 1; fi
        ;;
    *)
        echo "usage: $0 {start|run|stop|status}" >&2; exit 2 ;;
esac
EOF

# Rewrites compose `configs` into bind mounts (podman-compose ignores them).
COPY --chmod=755 <<'EOF' /usr/local/bin/docker-shim-compose-fixup
#!/opt/venv/bin/python3
"""Rewrite a compose file so podman-compose 1.6.0 can run it.

podman-compose ignores top-level `configs:` and per-service `configs:` (it has
no equivalent of docker's config objects). This turns every config into a
plain file next to the compose file and replaces the service-level entries by
read-only bind mounts, which podman-compose does support.

Usage: docker-shim-compose-fixup <compose.yml> <project>
Writes the file in place; config contents go to
<dir>/.docker-shim.<project>.configs/<name>.
"""
import os
import stat
import sys

import yaml

path, project = sys.argv[1], sys.argv[2]
base = os.path.dirname(os.path.abspath(path))
with open(path) as fh:
    doc = yaml.safe_load(fh) or {}

configs = doc.pop("configs", None) or {}
if not configs:
    sys.exit(0)

cfg_dir = os.path.join(base, f".docker-shim.{project}.configs")
os.makedirs(cfg_dir, mode=0o700, exist_ok=True)

files = {}
for name, spec in configs.items():
    spec = spec or {}
    if "content" in spec:
        dest = os.path.join(cfg_dir, name)
        with open(dest, "w") as fh:
            fh.write(spec["content"])
        os.chmod(dest, stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH)
        files[name] = dest
    elif "file" in spec:
        files[name] = os.path.abspath(os.path.join(base, os.path.expanduser(spec["file"])))
    elif "environment" in spec:
        dest = os.path.join(cfg_dir, name)
        with open(dest, "w") as fh:
            fh.write(os.environ.get(spec["environment"], ""))
        files[name] = dest
    else:
        sys.stderr.write(f"docker-shim: config '{name}' has no content/file/environment, skipping\n")

for svc_name, svc in (doc.get("services") or {}).items():
    entries = (svc or {}).pop("configs", None) or []
    volumes = svc.setdefault("volumes", [])
    for entry in entries:
        if isinstance(entry, str):
            source, target = entry, f"/{entry}"
        else:
            source = entry.get("source")
            target = entry.get("target") or f"/{source}"
        if source not in files:
            sys.stderr.write(f"docker-shim: service '{svc_name}' references unknown config '{source}'\n")
            continue
        volumes.append(f"{files[source]}:{target}:ro")
    if not volumes:
        svc.pop("volumes", None)

with open(path, "w") as fh:
    yaml.safe_dump(doc, fh, default_flow_style=False, sort_keys=False)
EOF

# System-wide podman config (kept out of /home so it cannot drift)
COPY --chmod=644 <<'EOF' /etc/containers/containers.conf
# System-wide podman configuration for the cartesi-sandbox rootfs.
# Containers get their own pid and network namespaces (pasta); the sandbox's
# OCI config provides /dev/net/tun and an unmasked /proc so that works.
[containers]

[engine]
EOF

COPY --chmod=644 <<'EOF' /etc/containers/registries.conf
unqualified-search-registries = ["docker.io"]
EOF

RUN <<EOF
set -e
echo 'ubuntu:100000:65535' > /etc/subuid
echo 'ubuntu:100000:65535' > /etc/subgid
# mountpoint for the per-session tmpfs (XDG_RUNTIME_DIR) declared in sandbox-config.template.json
mkdir -p /run/user/1000
chown 1000:1000 /run/user/1000
chmod 700 /run/user/1000
EOF

################################################################################
# user install packages
FROM install AS user-install
USER ubuntu

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
ARG PODMAN_COMPOSE_VERSION

RUN <<EOF
# Ensure the venv is used for subsequent RUN and at runtime
pip3 install --no-cache cartesapp[dev]@git+https://github.com/prototyp3-dev/cartesapp@v${CARTESAPP_VERSION}
pip3 install --no-cache podman-compose==${PODMAN_COMPOSE_VERSION}
EOF

RUN cat <<'EOF' >> /home/ubuntu/.bashrc
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

export PODMAN_COMPOSE_WARNING_LOGS=false
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"

export PATH=/home/ubuntu/.local/bin:/opt/venv/bin:$PATH
EOF

USER root

# cleanup
RUN <<EOF
set -e
rm -rf /tmp/* /var/lib/apt/lists/* /var/log/* /var/cache/*
EOF

FROM user-install AS runtime

USER ubuntu
WORKDIR /home/ubuntu

