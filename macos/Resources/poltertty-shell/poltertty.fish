# Poltertty shell integration — PATH (fish)
# Always prepend POLTERTTY_BIN_DIR to PATH so the wrapper takes priority over system claude.
if set -q POLTERTTY_BIN_DIR
    set -e PATH[(contains -i -- $POLTERTTY_BIN_DIR $PATH)]
    set -gx PATH $POLTERTTY_BIN_DIR $PATH
end
