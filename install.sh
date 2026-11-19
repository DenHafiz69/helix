#!/bin/sh
set -eu

# Defaults (can be overridden via environment variables or CLI flags)
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
HELIX_CONFIG_DIR="${HELIX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/helix}"
HELIX_VERSION="${HELIX_VERSION:-}"
REPO_SLUG="${REPO_SLUG:-DenHafiz69/helix}"
BRANCH="${BRANCH:-main}"
CONFIG_FILES="config.toml languages.toml"

MODE="all"        # all | config-only | no-config
BACKUP_CONFIG=1   # 1 = backup differing existing configs, 0 = overwrite directly

# Colors (disabled when not a TTY or when NO_COLOR is set)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_BLUE='\033[1;34m'
    C_GREEN='\033[1;32m'
    C_YELLOW='\033[1;33m'
    C_RED='\033[1;31m'
    C_RESET='\033[0m'
else
    C_BLUE=''
    C_GREEN=''
    C_YELLOW=''
    C_RED=''
    C_RESET=''
fi

info() {
    printf '%b==>%b %s\n' "$C_BLUE" "$C_RESET" "$1"
}

subinfo() {
    printf '    %s\n' "$1"
}

success() {
    printf '%b==>%b %s\n' "$C_GREEN" "$C_RESET" "$1"
}

warn() {
    printf '%bWarning:%b %s\n' "$C_YELLOW" "$C_RESET" "$1" >&2
}

die() {
    printf '%bError:%b %s\n' "$C_RED" "$C_RESET" "$1" >&2
    exit 1
}

usage() {
    cat <<EOF
Helix Editor & Config Installer

Usage:
  install.sh [OPTIONS]

Options:
  -h, --help               Show this help message and exit
  -v, --version VERSION    Install a specific Helix version (e.g. 25.01.1)
      --install-dir DIR    Directory for the 'hx' binary (default: ~/.local/bin)
      --config-dir DIR     Directory for Helix config (default: ~/.config/helix)
      --config-only        Only install/update configuration files
      --no-config          Only install 'hx' binary and runtime (skip config files)
      --no-backup          Overwrite existing config files without creating backups

Environment Variables:
  INSTALL_DIR              Same as --install-dir
  HELIX_CONFIG_DIR         Same as --config-dir
  HELIX_VERSION            Same as --version
  REPO_SLUG                GitHub repo for remote configs (default: DenHafiz69/helix)
  BRANCH                   Git branch for remote configs (default: main)
  NO_COLOR                 Disable colored output when set
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                [ "$#" -ge 2 ] || die "Missing argument for $1"
                HELIX_VERSION="$2"
                shift 2
                ;;
            --version=*)
                HELIX_VERSION="${1#*=}"
                shift
                ;;
            --install-dir)
                [ "$#" -ge 2 ] || die "Missing argument for $1"
                INSTALL_DIR="$2"
                shift 2
                ;;
            --install-dir=*)
                INSTALL_DIR="${1#*=}"
                shift
                ;;
            --config-dir)
                [ "$#" -ge 2 ] || die "Missing argument for $1"
                HELIX_CONFIG_DIR="$2"
                shift 2
                ;;
            --config-dir=*)
                HELIX_CONFIG_DIR="${1#*=}"
                shift
                ;;
            --config-only)
                [ "$MODE" != "no-config" ] || die "Cannot combine --config-only and --no-config"
                MODE="config-only"
                shift
                ;;
            --no-config)
                [ "$MODE" != "config-only" ] || die "Cannot combine --config-only and --no-config"
                MODE="no-config"
                shift
                ;;
            --no-backup)
                BACKUP_CONFIG=0
                shift
                ;;
            *)
                die "Unknown option: $1 (run with --help for usage)"
                ;;
        esac
    done
}

download() {
    url="$1"
    dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url"
    else
        die "Neither 'curl' nor 'wget' is installed."
    fi
}

detect_platform() {
    info "Detecting platform..."
    OS="$(uname -s)"
    case "$OS" in
        Linux*)  OS_NAME="linux" ;;
        Darwin*) OS_NAME="macos" ;;
        *)       die "Unsupported OS '$OS'. Helix prebuilt binaries support Linux and macOS." ;;
    esac

    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64|amd64)  ARCH_NAME="x86_64" ;;
        arm64|aarch64) ARCH_NAME="aarch64" ;;
        *)             die "Unsupported architecture '$ARCH'." ;;
    esac

    subinfo "Platform: ${ARCH_NAME}-${OS_NAME}"
}

resolve_version() {
    if [ -n "$HELIX_VERSION" ]; then
        HELIX_VERSION="${HELIX_VERSION#v}"
        subinfo "Helix version (pinned): ${HELIX_VERSION}"
        return
    fi

    info "Finding latest Helix release..."
    REDIRECT_URL=""
    if command -v curl >/dev/null 2>&1; then
        REDIRECT_URL="$(curl -fsSIL -o /dev/null -w '%{url_effective}' https://github.com/helix-editor/helix/releases/latest)" || true
    elif command -v wget >/dev/null 2>&1; then
        REDIRECT_URL="$(wget -q --spider --server-response https://github.com/helix-editor/helix/releases/latest 2>&1 \
            | awk '/^[[:space:]]*[Ll]ocation:/{print $2}' \
            | tail -n 1 \
            | tr -d '\r')" || true
    else
        die "Neither 'curl' nor 'wget' is installed."
    fi

    HELIX_VERSION="$(basename "$REDIRECT_URL")"
    HELIX_VERSION="${HELIX_VERSION#v}"

    if [ -z "$HELIX_VERSION" ] || [ "$HELIX_VERSION" = "latest" ]; then
        die "Could not determine latest Helix release version. Specify one with --version."
    fi

    subinfo "Helix version: ${HELIX_VERSION}"
}

install_binary_and_runtime() {
    command -v tar >/dev/null 2>&1 || die "'tar' is required but not installed."
    command -v xz >/dev/null 2>&1 || die "'xz' is required to extract .tar.xz archives but is not installed."

    detect_platform
    resolve_version

    ASSET="helix-${HELIX_VERSION}-${ARCH_NAME}-${OS_NAME}.tar.xz"
    DOWNLOAD_URL="https://github.com/helix-editor/helix/releases/download/${HELIX_VERSION}/${ASSET}"

    info "Downloading Helix (${ASSET})..."
    if ! download "$DOWNLOAD_URL" "$TMP_DIR/$ASSET"; then
        die "Failed to download ${DOWNLOAD_URL}"
    fi

    info "Extracting archive..."
    tar -xf "$TMP_DIR/$ASSET" -C "$TMP_DIR"

    HX_BIN="$(find "$TMP_DIR" -type f -name hx | head -n 1)"
    [ -n "$HX_BIN" ] && [ -f "$HX_BIN" ] || die "Could not find 'hx' executable in extracted archive."

    RUNTIME_DIR="$(find "$TMP_DIR" -type d -name runtime | head -n 1)"

    info "Installing 'hx' binary to ${INSTALL_DIR}..."
    mkdir -p "$INSTALL_DIR"
    # Stage and atomically rename so an active 'hx' process won't trigger ETXTBSY
    cp "$HX_BIN" "$INSTALL_DIR/hx.tmp.$$"
    chmod 755 "$INSTALL_DIR/hx.tmp.$$"
    mv -f "$INSTALL_DIR/hx.tmp.$$" "$INSTALL_DIR/hx"

    if [ -n "$RUNTIME_DIR" ] && [ -d "$RUNTIME_DIR" ]; then
        info "Installing Helix runtime to ${HELIX_CONFIG_DIR}/runtime..."
        mkdir -p "$HELIX_CONFIG_DIR"
        rm -rf "$HELIX_CONFIG_DIR/runtime"
        cp -R "$RUNTIME_DIR" "$HELIX_CONFIG_DIR/runtime"
    fi
}

install_config_file() {
    src="$1"
    name="$(basename "$src")"
    dest="${HELIX_CONFIG_DIR}/${name}"

    if [ -f "$dest" ]; then
        if cmp -s "$src" "$dest"; then
            subinfo "Unchanged ${name} (already up to date)"
            return
        fi
        if [ "$BACKUP_CONFIG" -eq 1 ]; then
            backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
            cp "$dest" "$backup"
            subinfo "Backed up existing ${name} -> $(basename "$backup")"
        fi
    fi

    cp "$src" "$dest"
    subinfo "Installed ${name} -> ${HELIX_CONFIG_DIR}/"
}

resolve_script_dir() {
    if [ -n "$0" ] && [ -f "$0" ]; then
        cd "$(dirname "$0")" 2>/dev/null && pwd || true
    fi
}

install_configs() {
    info "Installing Helix configuration files..."
    mkdir -p "$HELIX_CONFIG_DIR"

    SCRIPT_DIR="$(resolve_script_dir)"
    SOURCE_DIR=""

    for candidate in "$SCRIPT_DIR" "$PWD"; do
        [ -n "$candidate" ] && [ -d "$candidate" ] || continue
        for cfg in $CONFIG_FILES; do
            if [ -f "${candidate}/${cfg}" ]; then
                SOURCE_DIR="$candidate"
                break 2
            fi
        done
    done

    if [ -n "$SOURCE_DIR" ]; then
        for cfg in $CONFIG_FILES; do
            if [ -f "${SOURCE_DIR}/${cfg}" ]; then
                install_config_file "${SOURCE_DIR}/${cfg}"
            fi
        done
    else
        subinfo "No local config files found. Fetching from ${REPO_SLUG} (${BRANCH})..."
        RAW_BASE="https://raw.githubusercontent.com/${REPO_SLUG}/${BRANCH}"
        for cfg in $CONFIG_FILES; do
            staged="${TMP_DIR}/${cfg}"
            if download "${RAW_BASE}/${cfg}" "$staged" 2>/dev/null; then
                install_config_file "$staged"
            else
                warn "${cfg} not found in remote repository (${RAW_BASE}/${cfg})."
            fi
        done
    fi
}

check_path() {
    case ":$PATH:" in
        *":$INSTALL_DIR:"*) ;;
        *)
            printf '\n'
            warn "'${INSTALL_DIR}' is not in your PATH."
            subinfo "Add it to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
            subinfo "  export PATH=\"\$PATH:${INSTALL_DIR}\""
            ;;
    esac
}

main() {
    parse_args "$@"

    TMP_DIR="$(mktemp -d)"
    cleanup() {
        rm -rf "$TMP_DIR"
    }
    trap cleanup EXIT INT TERM HUP

    if [ "$MODE" != "config-only" ]; then
        install_binary_and_runtime
    fi

    if [ "$MODE" != "no-config" ]; then
        install_configs
    fi

    printf '\n'
    success "Helix installation complete!"
    if [ "$MODE" != "config-only" ]; then
        if [ -x "${INSTALL_DIR}/hx" ]; then
            subinfo "Version: $("${INSTALL_DIR}/hx" --version 2>/dev/null || echo "${HELIX_VERSION}")"
        fi
        subinfo "Binary:  ${INSTALL_DIR}/hx"
    fi
    if [ "$MODE" != "no-config" ]; then
        subinfo "Config:  ${HELIX_CONFIG_DIR}"
    fi

    if [ "$MODE" != "config-only" ]; then
        check_path
    fi
}

main "$@"
