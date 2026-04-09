#!/usr/bin/env bash
# scripts/fetch-bundled-tools.sh
# Downloads yazi, ya, and delta universal binaries for macOS.
set -euo pipefail

# Note: Downloads aarch64 (Apple Silicon) binaries only.
# yazi does not publish universal macOS binaries. x86_64 Macs are not supported.

YAZI_VERSION="${YAZI_VERSION:-26.1.22}"
DELTA_VERSION="${DELTA_VERSION:-0.18.2}"
LAZYGIT_VERSION="${LAZYGIT_VERSION:-0.61.0}"
CACHE_DIR="${PROJECT_DIR:-.}/.bundled-tools-cache"
OUTPUT_DIR="${1:-macos/Resources/bin}"

mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"

# --- yazi + ya ---
YAZI_ARCHIVE="yazi-aarch64-apple-darwin.zip"
YAZI_URL="https://github.com/sxyazi/yazi/releases/download/v${YAZI_VERSION}/${YAZI_ARCHIVE}"
if [ ! -f "$CACHE_DIR/yazi-${YAZI_VERSION}" ] || [ ! -f "$OUTPUT_DIR/yazi" ]; then
    echo "Downloading yazi v${YAZI_VERSION}..."
    curl -fSL "$YAZI_URL" -o "$CACHE_DIR/${YAZI_ARCHIVE}"
    unzip -o "$CACHE_DIR/${YAZI_ARCHIVE}" -d "$CACHE_DIR/yazi-extract"
    cp "$CACHE_DIR/yazi-extract/yazi-aarch64-apple-darwin/yazi" "$OUTPUT_DIR/yazi"
    cp "$CACHE_DIR/yazi-extract/yazi-aarch64-apple-darwin/ya" "$OUTPUT_DIR/ya"
    chmod +x "$OUTPUT_DIR/yazi" "$OUTPUT_DIR/ya"
    touch "$CACHE_DIR/yazi-${YAZI_VERSION}"
fi

# --- delta ---
DELTA_ARCHIVE="delta-${DELTA_VERSION}-aarch64-apple-darwin.tar.gz"
DELTA_URL="https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/${DELTA_ARCHIVE}"
if [ ! -f "$CACHE_DIR/delta-${DELTA_VERSION}" ] || [ ! -f "$OUTPUT_DIR/delta" ]; then
    echo "Downloading delta v${DELTA_VERSION}..."
    curl -fSL "$DELTA_URL" -o "$CACHE_DIR/${DELTA_ARCHIVE}"
    tar xzf "$CACHE_DIR/${DELTA_ARCHIVE}" -C "$CACHE_DIR"
    cp "$CACHE_DIR/delta-${DELTA_VERSION}-aarch64-apple-darwin/delta" "$OUTPUT_DIR/delta"
    chmod +x "$OUTPUT_DIR/delta"
    touch "$CACHE_DIR/delta-${DELTA_VERSION}"
fi

# --- lazygit ---
LAZYGIT_ARCHIVE="lazygit_${LAZYGIT_VERSION}_Darwin_arm64.tar.gz"
LAZYGIT_URL="https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/${LAZYGIT_ARCHIVE}"
if [ ! -f "$CACHE_DIR/lazygit-${LAZYGIT_VERSION}" ] || [ ! -f "$OUTPUT_DIR/lazygit" ]; then
    echo "Downloading lazygit v${LAZYGIT_VERSION}..."
    curl -fSL "$LAZYGIT_URL" -o "$CACHE_DIR/${LAZYGIT_ARCHIVE}"
    mkdir -p "$CACHE_DIR/lazygit-extract-${LAZYGIT_VERSION}"
    tar xzf "$CACHE_DIR/${LAZYGIT_ARCHIVE}" -C "$CACHE_DIR/lazygit-extract-${LAZYGIT_VERSION}"
    cp "$CACHE_DIR/lazygit-extract-${LAZYGIT_VERSION}/lazygit" "$OUTPUT_DIR/lazygit"
    chmod +x "$OUTPUT_DIR/lazygit"
    touch "$CACHE_DIR/lazygit-${LAZYGIT_VERSION}"
fi

# --- ad-hoc code signing ---
for bin in "$OUTPUT_DIR/yazi" "$OUTPUT_DIR/ya" "$OUTPUT_DIR/delta" "$OUTPUT_DIR/lazygit"; do
    if [ -f "$bin" ]; then
        codesign --force --sign - "$bin" 2>/dev/null || true
    fi
done

echo "Bundled tools ready in $OUTPUT_DIR"
