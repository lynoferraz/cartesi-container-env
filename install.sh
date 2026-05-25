#!/bin/sh
# cartesi-sandbox bootstrap installer.
#
#   curl -fsSL https://raw.githubusercontent.com/lynoferraz/cartesi-container-env/main/install.sh | sh
#
# Pass extra args after `--` :
#   curl -fsSL .../install.sh | sh -s -- --from-source
#   curl -fsSL .../install.sh | sh -s -- --tag v0.1.0
#
# Or skip the rootfs download and just place the script:
#   curl -fsSL .../install.sh | sh -s -- --no-install
#
# Specify the script version to install (defaults to latest tag, or specified tag):
#   curl -fsSL .../install.sh | sh -s -- --branch v0.1.0
set -eu

REPO="${CARTESI_SANDBOX_REPO:-lynoferraz/cartesi-container-env}"
BRANCH="${CARTESI_SANDBOX_BRANCH:-main}"
BIN_DIR="${CARTESI_SANDBOX_BIN_DIR:-$HOME/.local/bin}"

[ "$(uname -s)" = "Linux" ] || { echo "cartesi-sandbox requires Linux." >&2; exit 1; }
[ "$(id -u)" != "0" ]       || { echo "Do not run installer as root." >&2; exit 1; }

skip_install=0
for arg in "$@"; do
    [ "$arg" = "--no-install" ] && skip_install=1
done

for arg in "$@"; do
    if [ "$arg" = "--branch" ]; then
        if [ -n "${2:-}" ]; then
            BRANCH="$2"
        else
            echo "Error: --branch requires an argument." >&2
            exit 1
        fi
    fi
done
SCRIPT_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/cartesi-sandbox"


SCRIPT_TAG=${BRANCH}
if [ ${BRANCH} = "main" ]; then
    latest_tag=$(curl -s https://api.github.com/repos/${REPO}/tags | grep '"name":' | sed -E 's/.*"v([^"]+)".*/\1/' | head -n 1)
    SCRIPT_TAG=${latest_tag:-0.0.0}
fi

mkdir -p "$BIN_DIR"
echo "Downloading cartesi-sandbox -> $BIN_DIR/cartesi-sandbox"
curl -fsSL "$SCRIPT_URL" -o "$BIN_DIR/cartesi-sandbox"
chmod +x "$BIN_DIR/cartesi-sandbox"
sed -i "s/{{SCRIPT_TAG}}/$SCRIPT_TAG/g" "$BIN_DIR/cartesi-sandbox"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        echo
        echo "NOTE: $BIN_DIR is not on PATH. Add to your shell rc:"
        echo "  export PATH=\"$BIN_DIR:\$PATH\""
        echo
        ;;
esac

if [ "$skip_install" -eq 1 ]; then
    echo "Skipping rootfs install (--no-install). Run later:  cartesi-sandbox install"
    exit 0
fi

echo "Running first-time install (sudo will be requested for rootfs ownership)..."
# Filter out --no-install so it doesn't reach the subcommand.
filtered=""
last_arg=""
for arg in "$@"; do
    [ "$arg" = "--no-install" ] || [ "$arg" = "--branch" ] || [ "$last_arg" = "--branch" ] || filtered="$filtered $arg"
    last_arg="$arg"
done
# shellcheck disable=SC2086
exec "$BIN_DIR/cartesi-sandbox" install $filtered
