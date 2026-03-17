#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-}"

# 显示帮助信息
if [[ -z "$MODE" ]] || [[ "$MODE" == "-h" ]] || [[ "$MODE" == "--help" ]] || [[ "$MODE" == "help" ]]; then
    echo "Usage: $0 {dev|release} [--zip]"
    echo ""
    echo "Modes:"
    echo "  dev      - Build Debug configuration for development"
    echo "  release  - Build optimized Release configuration"
    echo ""
    echo "Options:"
    echo "  --zip    - Package as zip (release mode only)"
    exit 0
fi

cd "$REPO_ROOT"

# 根据模式设置参数
if [[ "$MODE" == "dev" ]]; then
    echo "==> Building in Dev mode (Debug configuration)"
    CONFIGURATION="Debug"
    SCHEME="Ghostty"
    OUTPUT_DIR="$REPO_ROOT/.build/DerivedData"

    # 运行 zig build 确保依赖存在
    echo "==> zig build (ensuring dependencies)"
    if ! zig build -Doptimize=Debug; then
        echo "ERROR: zig build failed. Fix zig errors before building."
        exit 1
    fi

    # 使用 xcodebuild 进行 Debug 构建（每个 worktree 使用独立的 DerivedData）
    echo "==> xcodebuild -configuration $CONFIGURATION"
    xcodebuild -project macos/Ghostty.xcodeproj \
               -scheme "$SCHEME" \
               -configuration "$CONFIGURATION" \
               -derivedDataPath "$OUTPUT_DIR" \
               build

    # 查找实际输出目录
    ACTUAL_OUTPUT=$(find "$OUTPUT_DIR" -name "Poltertty.app" -path "*/Debug/Poltertty.app" 2>/dev/null | head -n 1)

    if [[ -n "$ACTUAL_OUTPUT" ]]; then
        echo "==> done: $ACTUAL_OUTPUT"
        "$ACTUAL_OUTPUT/Contents/MacOS/ghostty" --version 2>&1 | grep "build mode\|version:" || true
    else
        echo "==> Build completed (app location may vary in DerivedData)"
    fi

elif [[ "$MODE" == "release" ]]; then
    echo "==> Building in Release mode (Optimized)"
    OPTIMIZE="ReleaseFast"
    OUTPUT_DIR="$REPO_ROOT/macos/build/ReleaseLocal"

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
else
    echo "Usage: $0 {dev|release} [--zip]"
    echo ""
    echo "Modes:"
    echo "  dev      - Build Debug configuration for development"
    echo "  release  - Build optimized Release configuration"
    echo ""
    echo "Options:"
    echo "  --zip    - Package as zip (release mode only)"
    exit 1
fi
