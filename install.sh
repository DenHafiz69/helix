#!/bin/sh
set -eu

# Configuration
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
HELIX_CONFIG_DIR="${HELIX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/helix}"
REPO_SLUG="${REPO_SLUG:-DenHafiz69/helix}"
BRANCH="${BRANCH:-main}"

echo "==> Detecting platform..."
OS="$(uname -s)"
case "$OS" in
    Linux*)     OS_NAME="linux" ;;
    Darwin*)    OS_NAME="macos" ;;
    *)
        echo "Error: Unsupported OS '$OS'. Helix prebuilt binaries support Linux and macOS." >&2
        exit 1
        ;;
esac

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64)   ARCH_NAME="x86_64" ;;
    arm64|aarch64)  ARCH_NAME="aarch64" ;;
    *)
        echo "Error: Unsupported architecture '$ARCH'." >&2
        exit 1
        ;;
esac

echo "    Platform detected: ${ARCH_NAME}-${OS_NAME}"

# Helper to download files
download() {
    url="$1"
    dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url"
    else
        echo "Error: Neither curl nor wget is installed." >&2
        exit 1
    fi
}

# Resolve Helix version
if [ -z "${HELIX_VERSION:-}" ]; then
    echo "==> Finding latest Helix release..."
    if command -v curl >/dev/null 2>&1; then
        REDIRECT_URL="$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/helix-editor/helix/releases/latest)"
        HELIX_VERSION="$(basename "$REDIRECT_URL")"
    elif command -v wget >/dev/null 2>&1; then
        REDIRECT_URL="$(wget -q --spider --server-response https://github.com/helix-editor/helix/releases/latest 2>&1 | awk '/Location: /{print $2}' | tail -n 1)"
        HELIX_VERSION="$(basename "$REDIRECT_URL")"
    fi
    HELIX_VERSION="${HELIX_VERSION#v}"
fi

if [ -z "$HELIX_VERSION" ] || [ "$HELIX_VERSION" = "latest" ]; then
    echo "Error: Could not determine latest Helix release version." >&2
    exit 1
fi

echo "    Helix version: ${HELIX_VERSION}"

# Check for tar
if ! command -v tar >/dev/null 2>&1; then
    echo "Error: tar is required but not installed." >&2
    exit 1
fi

# Create temporary directory
TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM HUP

ASSET="helix-${HELIX_VERSION}-${ARCH_NAME}-${OS_NAME}.tar.xz"
DOWNLOAD_URL="https://github.com/helix-editor/helix/releases/download/${HELIX_VERSION}/${ASSET}"

echo "==> Downloading Helix binary archive (${ASSET})..."
download "$DOWNLOAD_URL" "$TMP_DIR/$ASSET"

echo "==> Extracting archive..."
tar -xf "$TMP_DIR/$ASSET" -C "$TMP_DIR"

# Locate extracted binary and runtime directory
HX_BIN="$(find "$TMP_DIR" -type f -name hx | head -n 1)"
if [ -z "$HX_BIN" ] || [ ! -f "$HX_BIN" ]; then
    echo "Error: Could not find 'hx' executable in extracted archive." >&2
    exit 1
fi

RUNTIME_DIR="$(find "$TMP_DIR" -type d -name runtime | head -n 1)"

# Install binary
echo "==> Installing 'hx' binary to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
cp "$HX_BIN" "$INSTALL_DIR/hx"
chmod 755 "$INSTALL_DIR/hx"

# Prepare Helix config directory
mkdir -p "$HELIX_CONFIG_DIR"

# Install runtime if present
if [ -n "$RUNTIME_DIR" ] && [ -d "$RUNTIME_DIR" ]; then
    echo "==> Installing Helix runtime to ${HELIX_CONFIG_DIR}/runtime..."
    mkdir -p "$HELIX_CONFIG_DIR/runtime"
    cp -r "$RUNTIME_DIR/"* "$HELIX_CONFIG_DIR/runtime/"
fi

# Install .toml configuration files
echo "==> Installing Helix configuration files (*.toml)..."
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE:-}" ] && [ "$BASH_SOURCE" != "$0" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE")" 2>/dev/null && pwd)"
elif [ -n "$0" ] && [ -f "$0" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
fi

found_local=false
for dir in "$SCRIPT_DIR" "$PWD"; do
    if [ -n "$dir" ] && [ -d "$dir" ]; then
        toml_count="$(find "$dir" -maxdepth 1 -name "*.toml" 2>/dev/null | wc -l)"
        if [ "$toml_count" -gt 0 ]; then
            for toml_file in "$dir"/*.toml; do
                [ -e "$toml_file" ] || continue
                cp "$toml_file" "$HELIX_CONFIG_DIR/"
                echo "    Installed $(basename "$toml_file") -> ${HELIX_CONFIG_DIR}/"
            done
            found_local=true
            break
        fi
    fi
done

if [ "$found_local" = false ]; then
    echo "    No local .toml files found. Fetching from ${REPO_SLUG} (${BRANCH})..."
    RAW_BASE="https://raw.githubusercontent.com/${REPO_SLUG}/${BRANCH}"
    for cfg in config.toml languages.toml; do
        if download "${RAW_BASE}/${cfg}" "$HELIX_CONFIG_DIR/${cfg}" 2>/dev/null; then
            echo "    Downloaded ${cfg} -> ${HELIX_CONFIG_DIR}/"
        else
            echo "    Notice: ${cfg} not found in remote repository."
        fi
    done
fi

echo "==> Helix installation complete!"
echo "    Binary:  ${INSTALL_DIR}/hx"
echo "    Config:  ${HELIX_CONFIG_DIR}"

# Check if INSTALL_DIR is in PATH
case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
        echo ""
        echo "Notice: '${INSTALL_DIR}' is not in your PATH."
        echo "Add it to your shell profile (e.g. ~/.bashrc or ~/.zshrc):"
        echo "  export PATH=\"\$PATH:${INSTALL_DIR}\""
        ;;
esac
