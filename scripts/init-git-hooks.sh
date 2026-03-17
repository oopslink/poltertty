#!/bin/sh
# 初始化本地 Git Hooks，保护 main 分支不被直接推送

set -e

HOOKS_DIR="$(git rev-parse --git-dir)/hooks"
PRE_PUSH="$HOOKS_DIR/pre-push"

# 写入 pre-push hook
cat > "$PRE_PUSH" << 'EOF'
#!/bin/sh
# 禁止直接推送到 main 分支

while read local_ref local_sha remote_ref remote_sha; do
  if echo "$remote_ref" | grep -q "refs/heads/main"; then
    echo ""
    echo "  错误：禁止直接推送到 main 分支"
    echo "  请在 worktree 中开发，完成后通过 Pull Request 合并"
    echo ""
    exit 1
  fi
done

exit 0
EOF

chmod +x "$PRE_PUSH"

echo "Git hooks 初始化完成：$PRE_PUSH"
