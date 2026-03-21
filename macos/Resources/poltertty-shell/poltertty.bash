# Poltertty shell integration — PATH 补强 (bash)
# 防止用户 source ~/.bashrc 后 PATH 被重置导致 wrapper 失效
if [[ -n "$POLTERTTY_BIN_DIR" ]] && [[ ":$PATH:" != *":$POLTERTTY_BIN_DIR:"* ]]; then
    export PATH="$POLTERTTY_BIN_DIR:$PATH"
fi
