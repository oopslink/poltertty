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
