# Poltertty shell integration — PATH 补强 (fish)
# 防止用户 source config.fish 后 PATH 被重置导致 wrapper 失效
if set -q POLTERTTY_BIN_DIR; and not contains -- $POLTERTTY_BIN_DIR $PATH
    set -gx PATH $POLTERTTY_BIN_DIR $PATH
end
