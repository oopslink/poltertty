# Poltertty shell integration — PATH (bash)
# Always prepend POLTERTTY_BIN_DIR to PATH so the wrapper takes priority over system claude.
if [[ -n "$POLTERTTY_BIN_DIR" ]]; then
    PATH="${POLTERTTY_BIN_DIR}:${PATH//:$POLTERTTY_BIN_DIR/}"
    export PATH
fi
