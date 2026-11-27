#!/usr/bin/env bash
set -euo pipefail

# Default configuration
VERSION_STR=$(date +%Y%m%d)
OUT_DIR="$(pwd)/dist/"
XZ_LEVEL="6"
INCLUDE_ODIN=false
BOOT_IMG="/tmp/postmarketOS-export/boot.img"
ROOTFS_IMG="/tmp/postmarketOS-export/samsung-gta8.img"
DTBO_IMG="$(pwd)/firmware/dtbo-noop.img"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Optional:
  -b, --boot <path>       Path to boot.img (default: ${BOOT_IMG})
  -r, --rootfs <path>     Path to rootfs.img (default: ${ROOTFS_IMG})
  -d, --dtbo <path>       Path to custom or no-op dtbo.img (default: ${DTBO_IMG})
  -v, --version <version> Release version string (default: ${VERSION_STR})
  -o, --out-dir <dir>     Output directory (default: ${OUT_DIR})
  -l, --level <1-9>       xz compression level (default: ${XZ_LEVEL}; use 9 for smallest size)
      --odin              Also bundle boot.img (+ dtbo.img) into an Odin-comaptible .tar
  -h, --help              Show this help message

Example:
  $(basename "$0") \\
    -b /tmp/postmarketOS-export/boot.img \\
    -r /tmp/postmarketOS-export/samsung-gtaba8.img \\
    -d ./firmware/dtbo-noop.img \\
    -v alpha1 \\
    -o ./dist \\
    --odin
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--boot)    BOOT_IMG="${2:-}"; shift 2 ;;
        -r|--rootfs)  ROOTFS_IMG="${2:-}"; shift 2 ;;
        -d|--dtbo)    DTBO_IMG="${2:-}"; shift 2 ;;
        -v|--version) VERSION_STR="${2:-}"; shift 2 ;;
        -o|--out-dir) OUT_DIR="${2:-}"; shift 2 ;;
        -l|--level)   XZ_LEVEL="${2:-}"; shift 2 ;;
        --odin)       INCLUDE_ODIN=true; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "Error: Unknown option '$1'" >&2; usage >&2; exit 1 ;;
    esac
done

# Validate inputs and dependencies
for cmd in tar xz sha256sum realpath; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' is required." >&2; exit 1; }
done

if ! [[ "$XZ_LEVEL" =~ ^[1-9]$ ]]; then
    echo "Error: Compression level must be an integer between 1 and 9." >&2
    exit 1
fi

RELEASE_NAME="nura-edge-samsung-gta8-${VERSION_STR}"
BOOT_ABS="$(realpath -e "$BOOT_IMG")"
ROOTFS_ABS="$(realpath -e "$ROOTFS_IMG")"
DTBO_ABS=""
[[ -n "$DTBO_IMG" ]] && DTBO_ABS="$(realpath -e "$DTBO_IMG")"

mkdir -p "$OUT_DIR"
OUT_ABS="$(realpath -e "$OUT_DIR")"

# Create staging directory in OUT_DIR to avoid filling a small RAM-backed /tmp
STAGE_DIR="$(mktemp -d "${OUT_ABS}/.bundle-stage.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT

BUNDLE_DIR="${STAGE_DIR}/${RELEASE_NAME}"
mkdir -p "$BUNDLE_DIR"

# Symlink inputs with normalised filenames (zero-copy staging)
ln -s "$BOOT_ABS" "${BUNDLE_DIR}/boot.img"
ln -s "$ROOTFS_ABS" "${BUNDLE_DIR}/rootfs.img"
CHECKSUM_FILES=(boot.img rootfs.img)

if [[ -n "$DTBO_ABS" ]]; then
    ln -s "$DTBO_ABS" "${BUNDLE_DIR}/dtbo.img"
    CHECKSUM_FILES+=(dtbo.img)
fi

# Optionally build an uncompressed ustar archive for Windows Odin users
if [[ "$INCLUDE_ODIN" == true ]]; then
    ODIN_FILES=(boot.img)
    [[ -n "$DTBO_ABS" ]] && ODIN_FILES+=(dtbo.img)
    echo "Creating Odin-compatible boot archive..."
    tar -h -H ustar -C "$BUNDLE_DIR" -cf "${BUNDLE_DIR}/odin-boot.tar" "${ODIN_FILES[@]}"
    CHECKSUM_FILES+=(odin-boot.tar)
fi

echo "Calculating internal SHA-256 checksums..."
(
    cd "$BUNDLE_DIR"
    sha256sum "${CHECKSUM_FILES[@]}" > SHA256SUMS
)

ARCHIVE_PATH="${OUT_ABS}/${RELEASE_NAME}.tar.xz"
echo "Compressing archive with xz (level ${XZ_LEVEL}, all CPU threads)..."
tar -h -C "$STAGE_DIR" -cf - "$RELEASE_NAME" \
    | xz -T0 "-${XZ_LEVEL}" -c > "$ARCHIVE_PATH"

echo "Calculating archive checksum..."
(
    cd "$OUT_ABS"
    sha256sum "$(basename "$ARCHIVE_PATH")" > "$(basename "$ARCHIVE_PATH").sha256"
)

echo
echo "Done:"
ls -lh "$ARCHIVE_PATH" "${ARCHIVE_PATH}.sha256"