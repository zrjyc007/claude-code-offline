#!/usr/bin/env bash
# =============================================================================
# Common utilities for Claude Code offline scripts
# =============================================================================
# Usage: source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
# =============================================================================

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# ---------------------------------------------------------------------------
# Command helpers
# ---------------------------------------------------------------------------
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Network helpers
# ---------------------------------------------------------------------------
test_url_accessible() {
    local url="$1"
    local timeout="${2:-10}"

    if command_exists curl; then
        curl -fsSL --max-time "$timeout" --retry 2 -I "$url" >/dev/null 2>&1
    elif command_exists wget; then
        wget --timeout="$timeout" --tries=2 -q --spider "$url" 2>/dev/null
    else
        return 1
    fi
}

download_with_mirrors() {
    local output_file="$1"
    shift
    local mirrors=("$@")
    local success=false

    for mirror in "${mirrors[@]}"; do
        log_info "Trying mirror: $mirror"

        if command_exists curl; then
            if curl -fsSL --max-time 10 --retry 2 \
                    -o "$output_file" "$mirror" 2>/dev/null; then
                success=true
                log_ok "Downloaded from: $mirror"
                break
            fi
        elif command_exists wget; then
            if wget --timeout=10 --tries=2 \
                    -q -O "$output_file" "$mirror" 2>/dev/null; then
                success=true
                log_ok "Downloaded from: $mirror"
                break
            fi
        fi

        log_warn "Failed to download from: $mirror"
    done

    if [ "$success" = true ]; then
        return 0
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Platform detection
# Returns: os-arch (e.g., linux-amd64)
# ---------------------------------------------------------------------------
detect_platform() {
    local os
    local arch

    case "$(uname -s)" in
        Linux*)     os="linux" ;;
        Darwin*)    os="macos" ;;
        CYGWIN*|MINGW*|MSYS*) os="windows" ;;
        *)          log_error "Unsupported OS: $(uname -s)"; exit 1 ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)   arch="amd64" ;;
        aarch64|arm64)   arch="arm64" ;;
        armv7l|armhf)    arch="armhf" ;;
        *)               log_error "Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac

    echo "${os}-${arch}"
}

# ---------------------------------------------------------------------------
# jq initialization (system or bundled)
# Sets global JQ_CMD variable
# ---------------------------------------------------------------------------
init_jq() {
    # Check if system jq is available
    if command -v jq &> /dev/null; then
        JQ_CMD="jq"
        return 0
    fi

    # Search for bundled jq in candidate directories
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    local jq_dirs=()
    # When sourced from skills/lib/common.sh, the script dir is skills/lib/
    # Candidate paths relative to lib/:
    jq_dirs+=("${script_dir}/../bin")                    # old path
    jq_dirs+=("${script_dir}/../../tools/jq")            # new path (skills/ sibling to tools/)
    jq_dirs+=("${script_dir}/../../bin")                 # old path from lib/
    jq_dirs+=("${script_dir}/../../../tools/jq")         # deeply nested case
    # Also check paths relative to the calling script (if different)
    if [ -n "${CALLER_DIR:-}" ]; then
        jq_dirs+=("${CALLER_DIR}/bin")
        jq_dirs+=("${CALLER_DIR}/../tools/jq")
        jq_dirs+=("${CALLER_DIR}/../../tools/jq")
    fi

    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    local platform_suffix=""
    case "$os" in
        Linux*)
            case "$arch" in
                x86_64|amd64)   platform_suffix="linux-amd64/jq" ;;
                aarch64|arm64)   platform_suffix="linux-arm64/jq" ;;
                armv7l|armhf)    platform_suffix="linux-armhf/jq" ;;
            esac
            ;;
        Darwin*)
            case "$arch" in
                x86_64|amd64)   platform_suffix="macos-amd64/jq" ;;
                arm64)           platform_suffix="macos-arm64/jq" ;;
            esac
            ;;
        CYGWIN*|MINGW*|MSYS*)
            platform_suffix="windows-amd64/jq.exe"
            ;;
    esac

    for jq_dir in "${jq_dirs[@]}"; do
        if [ -n "$platform_suffix" ]; then
            local candidate="${jq_dir}/${platform_suffix}"
            if [ -x "$candidate" ]; then
                JQ_CMD="$candidate"
                return 0
            fi
        fi
    done

    # Check for jq wrapper script
    for jq_dir in "${jq_dirs[@]}"; do
        local wrapper="${jq_dir}/jq-wrapper.sh"
        if [ -f "$wrapper" ] && [ -x "$wrapper" ]; then
            JQ_CMD="bash ${wrapper}"
            return 0
        fi
    done

    return 1
}
