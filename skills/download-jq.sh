#!/usr/bin/env bash
# =============================================================================
# Download jq binary for offline deployment
# =============================================================================
# Downloads jq binary for the current platform and architecture
# Usage: bash download-jq.sh [options] [output_dir]
# Default: ./bin/
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/bin"
JQ_VERSION="1.7.1"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh"

# Download jq binary
download_jq() {
    local platform="$1"
    local output_path="${OUTPUT_DIR}/jq"

    log_info "Downloading jq ${JQ_VERSION} for ${platform}"

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Determine download URL based on platform
    local download_url
    case "$platform" in
        linux-amd64)
            download_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64"
            ;;
        linux-arm64)
            download_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-arm64"
            ;;
        linux-armhf)
            download_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-armhf"
            ;;
        macos-amd64)
            download_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-macos-amd64"
            ;;
        macos-arm64)
            download_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-macos-arm64"
            ;;
        windows-amd64)
            download_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-windows-amd64.exe"
            output_path="${OUTPUT_DIR}/jq.exe"
            ;;
        *)
            log_error "Unsupported platform: ${platform}"
            exit 1
            ;;
    esac

    # Download jq binary
    log_info "Downloading from: ${download_url}"
    if curl -fsSL "$download_url" -o "$output_path" 2>/dev/null; then
        chmod +x "$output_path"
        log_ok "jq downloaded to: ${output_path}"
        log_info "jq version: $($output_path --version 2>/dev/null || echo 'unknown')"
        return 0
    else
        log_error "Failed to download jq from: ${download_url}"
        return 1
    fi
}

# Download jq for all platforms (for offline package)
download_jq_all_platforms() {
    local output_dir="${OUTPUT_DIR}"

    log_info "Downloading jq for all platforms"

    # Create platform directories
    mkdir -p "$output_dir/linux-amd64"
    mkdir -p "$output_dir/linux-arm64"
    mkdir -p "$output_dir/macos-amd64"
    mkdir -p "$output_dir/macos-arm64"
    mkdir -p "$output_dir/windows-amd64"

    # Download for each platform in parallel
    local platforms=("linux-amd64" "linux-arm64" "macos-amd64" "macos-arm64" "windows-amd64")
    local tmp_results
    tmp_results=$(mktemp)

    for platform in "${platforms[@]}"; do
        local output_path
        if [[ "$platform" == *"windows"* ]]; then
            output_path="$output_dir/$platform/jq.exe"
        else
            output_path="$output_dir/$platform/jq"
        fi

        log_info "Downloading jq for ${platform}"
        (
            if download_jq_for_platform "$platform" "$output_path"; then
                echo "ok" >> "$tmp_results"
            else
                echo "fail" >> "$tmp_results"
            fi
        ) &
    done
    wait

    local success failed
    success=$(grep -c "^ok$" "$tmp_results" 2>/dev/null || echo 0)
    failed=$(grep -c "^fail$" "$tmp_results" 2>/dev/null || echo 0)
    rm -f "$tmp_results"

    log_info "============================="
    log_ok "Downloaded jq for ${success} platforms"
    if [ "$failed" -gt 0 ]; then
        log_warn "Failed: ${failed} platforms"
    fi

    return 0
}

# Download jq for a specific platform
download_jq_for_platform() {
    local platform="$1"
    local output_path="$2"

    # Determine download URL based on platform
    local download_url
    case "$platform" in
        linux-amd64)
            download_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64"
            ;;
        linux-arm64)
            download_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-arm64"
            ;;
        macos-amd64)
            download_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-macos-amd64"
            ;;
        macos-arm64)
            download_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-macos-arm64"
            ;;
        windows-amd64)
            download_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-windows-amd64.exe"
            ;;
        *)
            log_error "Unsupported platform: ${platform}"
            return 1
            ;;
    esac

    # Download jq binary
    if curl -fsSL "$download_url" -o "$output_path" 2>/dev/null; then
        chmod +x "$output_path"
        log_ok "  Downloaded: ${output_path}"
        return 0
    else
        log_error "  Failed to download: ${output_path}"
        return 1
    fi
}

# Create jq wrapper script
create_jq_wrapper() {
    local wrapper_path="${OUTPUT_DIR}/jq-wrapper.sh"

    log_info "Creating jq wrapper script"

    cat > "$wrapper_path" << 'EOF'
#!/usr/bin/env bash
# jq wrapper script for offline environments
# This script uses bundled jq if system jq is not available

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if system jq is available
if command -v jq &> /dev/null; then
    exec jq "$@"
fi

# Use bundled jq based on platform
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux*)
        case "$ARCH" in
            x86_64|amd64)   BUNDLED_JQ="${SCRIPT_DIR}/linux-amd64/jq" ;;
            aarch64|arm64)   BUNDLED_JQ="${SCRIPT_DIR}/linux-arm64/jq" ;;
            armv7l|armhf)    BUNDLED_JQ="${SCRIPT_DIR}/linux-armhf/jq" ;;
        esac
        ;;
    Darwin*)
        case "$ARCH" in
            x86_64|amd64)   BUNDLED_JQ="${SCRIPT_DIR}/macos-amd64/jq" ;;
            arm64)           BUNDLED_JQ="${SCRIPT_DIR}/macos-arm64/jq" ;;
        esac
        ;;
    CYGWIN*|MINGW*|MSYS*)
        BUNDLED_JQ="${SCRIPT_DIR}/windows-amd64/jq.exe"
        ;;
esac

if [ -n "$BUNDLED_JQ" ] && [ -x "$BUNDLED_JQ" ]; then
    exec "$BUNDLED_JQ" "$@"
else
    echo "ERROR: jq not found (neither system nor bundled)" >&2
    echo "Please install jq or ensure the bundled jq is available for your platform" >&2
    exit 1
fi
EOF

    chmod +x "$wrapper_path"
    log_ok "jq wrapper created: ${wrapper_path}"
}

# Show help
show_help() {
    echo "jq Downloader for Offline Deployment"
    echo ""
    echo "Usage: bash download-jq.sh [options] [output_dir]"
    echo ""
    echo "Options:"
    echo "  --all       Download jq for all platforms (linux, macos, windows)"
    echo "  -h, --help  Show this help message"
    echo ""
    echo "Arguments:"
    echo "  output_dir  Directory to save jq binaries (default: ./bin/)"
    echo ""
    echo "Examples:"
    echo "  bash download-jq.sh                    # Download for current platform"
    echo "  bash download-jq.sh --all              # Download for all platforms"
    echo "  bash download-jq.sh /path/to/bin       # Download to custom directory"
    echo "  bash download-jq.sh --all /path/to/bin # Download all platforms to custom directory"
}

# Main function
main() {
    log_info "jq Downloader for Offline Deployment"
    log_info "====================================="

    # Parse arguments
    local download_all=false
    local output_dir=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --all)
                download_all=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                output_dir="$1"
                shift
                ;;
        esac
    done

    # Set output directory if provided
    if [ -n "$output_dir" ]; then
        OUTPUT_DIR="$output_dir"
    fi

    # Download jq
    if [ "$download_all" = true ]; then
        download_jq_all_platforms
    else
        # Download for current platform only
        local platform
        platform=$(detect_platform)
        download_jq "$platform"
    fi

    # Create wrapper script
    create_jq_wrapper

    log_info "======================================="
    log_ok "jq download completed!"
    log_info "Output directory: ${OUTPUT_DIR}"
    log_info "Usage:"
    log_info "  System jq: jq [options] <expression> [file...]"
    log_info "  Bundled jq: bash ${OUTPUT_DIR}/jq-wrapper.sh [options] <expression> [file...]"
}

# Run main function
main "$@"
