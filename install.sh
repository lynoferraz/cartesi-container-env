#!/bin/sh
# cartesi-sandbox bootstrap installer.
#
#   curl -fsSL https://raw.githubusercontent.com/lynoferraz/cartesi-container-env/main/install.sh | sh
#
# Pass extra args after `--` :
#   curl -fsSL .../install.sh | sh -s -- --from-source   # build the rootfs locally from the
#                                                        # Dockerfile only (needs docker buildx)
#   curl -fsSL .../install.sh | sh -s -- --tag v0.1.0    # install this release (or, with
#                                                        # --from-source, build this ref)
#
# Or skip the rootfs download and just place the script:
#   curl -fsSL .../install.sh | sh -s -- --no-install
#
# Specify the branch/tag the cartesi-sandbox script, Dockerfile and config template are
# fetched from (defaults to main; the script version is then the latest tag):
#   curl -fsSL .../install.sh | sh -s -- --branch v0.1.0
set -eu

REPO="${CARTESI_SANDBOX_REPO:-lynoferraz/cartesi-container-env}"
BRANCH="${CARTESI_SANDBOX_BRANCH:-main}"
BIN_DIR="${CARTESI_SANDBOX_BIN_DIR:-$HOME/.local/bin}"

[ "$(uname -s)" = "Linux" ] || { echo "cartesi-sandbox requires Linux." >&2; exit 1; }
[ "$(id -u)" != "0" ]       || { echo "Do not run installer as root." >&2; exit 1; }

# --no-install and --branch are handled here; everything else (--from-source, --tag ...)
# is passed through to `cartesi-sandbox install`.
skip_install=0
passthrough=""
while [ $# -gt 0 ]; do
    case "$1" in
        --no-install) skip_install=1 ;;
        --branch)
            [ -n "${2:-}" ] || { echo "Error: --branch requires an argument." >&2; exit 1; }
            BRANCH="$2"; shift ;;
        --branch=*) BRANCH="${1#--branch=}" ;;
        *) passthrough="$passthrough $1" ;;
    esac
    shift
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
# The installed script fetches the Dockerfile (--from-source) and the config template
# from this branch/tag too.
export CARTESI_SANDBOX_BRANCH="$BRANCH"
# shellcheck disable=SC2086
exec "$BIN_DIR/cartesi-sandbox" install $passthrough
