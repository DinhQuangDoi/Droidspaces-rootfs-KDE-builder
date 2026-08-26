#!/usr/bin/env bash
# install-noctalia.sh — Downloads and installs pre-built Noctalia release artifact.
# Usage: ./install-noctalia.sh [target_dir]

set -euo pipefail

TARGET_DIR="${1:-/}"
NOCTALIA_RELEASE_REPO="${NOCTALIA_RELEASE_REPO:-DinhQuangDoi/noctalia-arm64}"
NOCTALIA_RELEASE_TAG="${NOCTALIA_RELEASE_TAG:-noctalia-arm64}"
DOWNLOAD_URL="https://github.com/${NOCTALIA_RELEASE_REPO}/releases/download/${NOCTALIA_RELEASE_TAG}/noctalia-arm64.tar.gz"

echo "=== Installing Noctalia from ${DOWNLOAD_URL} ==="

TMP_TAR="/tmp/noctalia-install-$$.tar.gz"
trap 'rm -f "$TMP_TAR"' EXIT

curl -fsSL "$DOWNLOAD_URL" -o "$TMP_TAR"

echo "=== Extracting Noctalia artifact into ${TARGET_DIR} ==="
tar -xzf "$TMP_TAR" -C "$TARGET_DIR"

# Ensure assets are present in both /usr/local/share and /usr/share for runtime lookup
if [ -d "${TARGET_DIR}/usr/local/share/noctalia/assets" ]; then
    mkdir -p "${TARGET_DIR}/usr/share/noctalia"
    cp -r "${TARGET_DIR}/usr/local/share/noctalia/assets" "${TARGET_DIR}/usr/share/noctalia/" 2>/dev/null || true
fi

# Ensure executable permissions
chmod 755 "${TARGET_DIR}/usr/local/bin/noctalia" 2>/dev/null || true
if [ -f "${TARGET_DIR}/usr/bin/noctalia" ]; then
    chmod 755 "${TARGET_DIR}/usr/bin/noctalia" 2>/dev/null || true
fi

echo "=== Noctalia installation completed successfully ==="
