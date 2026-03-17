#!/bin/bash
# Poltertty 一键发布脚本
# 用法: ./scripts/release.sh <version> [release_notes]
# 示例: ./scripts/release.sh 0.1.3 "修复若干 bug，优化性能"
#       ./scripts/release.sh 0.1.3  # 不传 notes 则交互式输入

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ─── 颜色 ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${CYAN}==> $*${NC}"; }
ok()    { echo -e "${GREEN}✓ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠ $*${NC}"; }
die()   { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

# ─── 参数 ────────────────────────────────────────────────────────────────────
VERSION="${1:-}"
NOTES="${2:-}"

if [[ -z "$VERSION" ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "用法: $0 <version> [release_notes]"
    echo ""
    echo "  version       新版本号，如 0.1.3"
    echo "  release_notes 发布说明（可选，不传则交互输入）"
    echo ""
    echo "示例:"
    echo "  $0 0.1.3"
    echo "  $0 0.1.3 \"修复若干 bug\""
    exit 0
fi

# 版本格式校验
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "版本号格式错误：$VERSION（应为 X.Y.Z）"
fi

TAG="v${VERSION}"

# ─── 环境检查 ────────────────────────────────────────────────────────────────
info "检查环境..."
command -v gh    >/dev/null || die "未找到 gh CLI，请先安装：brew install gh"
command -v zig   >/dev/null || die "未找到 zig"
command -v git   >/dev/null || die "未找到 git"
gh auth status >/dev/null 2>&1 || die "gh 未登录，请先运行：gh auth login"

# 当前分支必须是 main
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    die "当前分支是 '$CURRENT_BRANCH'，请先切到 main 分支"
fi

# 确保 main 与远程同步
info "同步 main 分支..."
git pull origin main --ff-only || die "main 同步失败，请手动处理冲突"

# Tag 不能已存在
if git tag | grep -q "^${TAG}$"; then
    die "Tag $TAG 已存在，请检查版本号"
fi

# 工作区必须干净
if ! git diff --quiet || ! git diff --cached --quiet; then
    die "工作区有未提交的改动，请先处理"
fi

# ─── 当前版本 ────────────────────────────────────────────────────────────────
CURRENT_VERSION="$(grep -o '\.version = "[^"]*"' build.zig.zon | grep -o '"[^"]*"' | tr -d '"')"
info "当前版本：$CURRENT_VERSION  →  新版本：$VERSION"

# ─── Release Notes ───────────────────────────────────────────────────────────
if [[ -z "$NOTES" ]]; then
    echo ""
    warn "请输入 Release Notes（输入完成后按 Ctrl+D）："
    NOTES="$(cat)"
fi

if [[ -z "$NOTES" ]]; then
    NOTES="Poltertty ${TAG} 发布"
fi

# ─── 步骤 1：更新版本号 ──────────────────────────────────────────────────────
info "更新版本号..."

sed -i '' "s/\\.version = \"${CURRENT_VERSION}\"/.version = \"${VERSION}\"/" build.zig.zon

# 只替换 poltertty 目标的版本（格式如 0.x.x，不替换 1.0）
sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${VERSION};/g" \
    macos/Ghostty.xcodeproj/project.pbxproj

# 验证
UPDATED="$(grep -o '\.version = "[^"]*"' build.zig.zon | grep -o '"[^"]*"' | tr -d '"')"
[[ "$UPDATED" == "$VERSION" ]] || die "build.zig.zon 版本更新失败"
ok "版本号已更新"

# ─── 步骤 2：创建 PR 并合并 ──────────────────────────────────────────────────
BRANCH="release/${TAG}"
info "创建分支 $BRANCH..."
git checkout -b "$BRANCH"

git add build.zig.zon macos/Ghostty.xcodeproj/project.pbxproj
git commit -m "chore: bump version to ${VERSION}"

info "推送分支..."
git push -u origin "$BRANCH"

info "创建 PR..."
PR_URL="$(gh pr create \
    --title "chore: bump version to ${VERSION}" \
    --body "$(cat <<EOF
## Release ${TAG}

版本号更新：\`${CURRENT_VERSION}\` → \`${VERSION}\`

**合并后自动触发构建和发布。**
EOF
    )")"

ok "PR 已创建：$PR_URL"

info "合并 PR..."
gh pr merge "$BRANCH" --merge --delete-branch
ok "PR 已合并"

# ─── 步骤 3：切回 main，打 tag ───────────────────────────────────────────────
info "切回 main..."
git checkout main
git pull origin main --ff-only

info "创建 tag $TAG..."
git tag -a "$TAG" -m "Release ${VERSION}"
ok "Tag $TAG 已创建"

# ─── 步骤 4：构建打包 ────────────────────────────────────────────────────────
info "开始构建（make package）..."
make package

ZIP_PATH="$REPO_ROOT/macos/build/Poltertty-${TAG}.zip"
[[ -f "$ZIP_PATH" ]] || die "打包产物不存在：$ZIP_PATH"
ZIP_SIZE="$(du -sh "$ZIP_PATH" | cut -f1)"
ok "构建完成：$ZIP_PATH（$ZIP_SIZE）"

# ─── 步骤 5：推送 tag ───────────────────────────────────────────────────────
info "推送 tag..."
git push origin "$TAG"
ok "Tag 已推送"

# ─── 步骤 6：创建 GitHub Release ────────────────────────────────────────────
info "创建 GitHub Release..."

RELEASE_BODY="$(cat <<EOF
${NOTES}

---
**下载安装**：解压 \`Poltertty-${TAG}.zip\`，将 Poltertty.app 拖入 Applications 文件夹。
EOF
)"

RELEASE_URL="$(gh release create "$TAG" "$ZIP_PATH" \
    --title "Poltertty ${TAG}" \
    --notes "$RELEASE_BODY")"

ok "GitHub Release 已创建：$RELEASE_URL"

# ─── 完成 ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Poltertty ${TAG} 发布完成！              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  Release : $RELEASE_URL"
echo "  包大小  : $ZIP_SIZE"
echo ""
