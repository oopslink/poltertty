#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPTIMIZE="${1:-ReleaseFast}"
OUTPUT_DIR="$REPO_ROOT/macos/build/ReleaseLocal"

cd "$REPO_ROOT"

echo "==> zig build -Doptimize=$OPTIMIZE"
zig build -Doptimize="$OPTIMIZE"

echo "==> codesign"
codesign --force --deep --sign - "$OUTPUT_DIR/Poltertty.app"

echo "==> done: $OUTPUT_DIR/Poltertty.app"
"$OUTPUT_DIR/Poltertty.app/Contents/MacOS/ghostty" --version 2>&1 | grep "build mode\|version:"

# 打包（使用 ditto 保留符号链接，避免普通 zip 解压报错）
if [[ "${2}" == "--zip" ]]; then
    VERSION=$(cd "$REPO_ROOT" && git describe --tags --abbrev=0 2>/dev/null || echo "dev")
    ZIP_PATH="$REPO_ROOT/macos/build/Poltertty-${VERSION}.zip"
    echo "==> packaging $ZIP_PATH"
    ditto -c -k --keepParent "$OUTPUT_DIR/Poltertty.app" "$ZIP_PATH"
    echo "==> zip: $ZIP_PATH ($(du -sh "$ZIP_PATH" | cut -f1))"
fi
