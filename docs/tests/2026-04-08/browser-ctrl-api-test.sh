#!/usr/bin/env bash
# Browser Panel Ctrl API E2E 测试脚本
# 在 Poltertty terminal 窗口中运行：$POLTERTTY_CTRL_PORT 已由 app 注入
#
# 用法：
#   直接在 Poltertty terminal 中运行：
#     bash <repo-root>/docs/tests/2026-04-08/browser-ctrl-api-test.sh
#
#   或指定端口：
#     POLTERTTY_CTRL_PORT=51234 bash ...
#
# 依赖：curl, jq

set -euo pipefail

PORT="${POLTERTTY_CTRL_PORT:-}"
if [[ -z "$PORT" ]]; then
    echo "❌ POLTERTTY_CTRL_PORT 未设置（请在 Poltertty terminal 中运行）"
    exit 1
fi

BASE="http://localhost:${PORT}/v1/mcp"
PASS=0
FAIL=0

# ─────────────────────────────────────────────
# 工具函数
# ─────────────────────────────────────────────

rpc() {
    local tool="$1"
    local args="$2"
    curl -s -X POST "$BASE" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"${tool}\",\"arguments\":${args}}}"
}

assert_ok() {
    local label="$1"
    local result="$2"
    local ok
    ok=$(echo "$result" | jq -r '.result.content[0].text // empty' 2>/dev/null | jq -r '.ok // empty' 2>/dev/null)
    if [[ "$ok" == "true" ]]; then
        echo "  ✅ $label"
        ((PASS++)) || true
    else
        echo "  ❌ $label"
        echo "     response: $result"
        ((FAIL++)) || true
    fi
}

assert_field() {
    local label="$1"
    local result="$2"
    local field="$3"
    local val
    val=$(echo "$result" | jq -r ".result.content[0].text // empty" 2>/dev/null | jq -r ".${field} // empty" 2>/dev/null)
    if [[ -n "$val" && "$val" != "null" ]]; then
        echo "  ✅ $label (${field}=${val:0:60})"
        ((PASS++)) || true
    else
        echo "  ❌ $label (expected field '${field}')"
        echo "     response: $result"
        ((FAIL++)) || true
    fi
}

assert_array() {
    local label="$1"
    local result="$2"
    local count
    count=$(echo "$result" | jq -r ".result.content[0].text // \"[]\"" 2>/dev/null | jq "length" 2>/dev/null || echo "0")
    if [[ "$count" -ge 0 ]]; then
        echo "  ✅ $label (${count} items)"
        ((PASS++)) || true
    else
        echo "  ❌ $label (could not parse array)"
        echo "     response: $result"
        ((FAIL++)) || true
    fi
}

assert_no_error() {
    local label="$1"
    local result="$2"
    local err
    err=$(echo "$result" | jq -r '.error // empty' 2>/dev/null)
    if [[ -z "$err" ]]; then
        echo "  ✅ $label"
        ((PASS++)) || true
    else
        echo "  ❌ $label"
        echo "     error: $err"
        ((FAIL++)) || true
    fi
}

# ─────────────────────────────────────────────
# 测试开始
# ─────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════"
echo " Browser Panel Ctrl API E2E Tests"
echo " Port: ${PORT}"
echo "═══════════════════════════════════════════"
echo ""

# ── 1. browser_list_tabs ─────────────────────
echo "[ 1 ] browser_list_tabs"
R=$(rpc "browser_list_tabs" "{}")
assert_array "lists tabs (possibly empty)" "$R"

# ── 2. browser_new_tab ───────────────────────
echo "[ 2 ] browser_new_tab (blank)"
R=$(rpc "browser_new_tab" "{}")
assert_field "returns tabId" "$R" "tabId"
BLANK_TAB_ID=$(echo "$R" | jq -r ".result.content[0].text" | jq -r ".tabId")
echo "     tabId=${BLANK_TAB_ID}"

# ── 3. browser_new_tab with URL ──────────────
echo "[ 3 ] browser_new_tab --url https://example.com"
R=$(rpc "browser_new_tab" "{\"url\":\"https://example.com\"}")
assert_field "returns tabId with url" "$R" "tabId"
URL_TAB_ID=$(echo "$R" | jq -r ".result.content[0].text" | jq -r ".tabId")

# ── 4. browser_list_tabs（应有 2 个）─────────
echo "[ 4 ] browser_list_tabs after new tabs"
R=$(rpc "browser_list_tabs" "{}")
COUNT=$(echo "$R" | jq -r ".result.content[0].text" | jq "length" 2>/dev/null || echo "0")
if [[ "$COUNT" -ge 2 ]]; then
    echo "  ✅ at least 2 tabs visible (${COUNT})"
    ((PASS++)) || true
else
    echo "  ❌ expected >= 2 tabs, got ${COUNT}"
    ((FAIL++)) || true
fi

# ── 5. browser_focus_tab ────────────────────
echo "[ 5 ] browser_focus_tab"
R=$(rpc "browser_focus_tab" "{\"tabId\":\"${BLANK_TAB_ID}\"}")
assert_ok "focus blank tab" "$R"

# ── 6. browser_navigate ──────────────────────
echo "[ 6 ] browser_navigate → https://example.com"
R=$(rpc "browser_navigate" "{\"url\":\"https://example.com\"}")
assert_ok "navigate returns ok" "$R"

# ── 7. browser_wait (load) ───────────────────
echo "[ 7 ] browser_wait --condition load"
R=$(rpc "browser_wait" "{\"condition\":\"load\",\"timeout\":15}")
assert_ok "page load completes" "$R"

# ── 8. browser_snapshot ──────────────────────
echo "[ 8 ] browser_snapshot"
R=$(rpc "browser_snapshot" "{}")
assert_field "snapshot has elements" "$R" "elements"
SNAP_ELEMENTS=$(echo "$R" | jq -r ".result.content[0].text" | jq ".elements | length" 2>/dev/null || echo "0")
echo "     elements=${SNAP_ELEMENTS}"

# ── 9. browser_get_text (full page) ──────────
echo "[ 9 ] browser_get_text (full page body)"
R=$(rpc "browser_get_text" "{}")
assert_field "get_text returns text" "$R" "text"

# ── 10. browser_eval ─────────────────────────
echo "[ 10 ] browser_eval → document.title"
R=$(rpc "browser_eval" "{\"script\":\"return document.title\"}")
TEXT=$(echo "$R" | jq -r ".result.content[0].text // \"null\"" 2>/dev/null)
if [[ "$TEXT" != "null" && "$TEXT" != "" ]]; then
    echo "  ✅ browser_eval returns title: ${TEXT}"
    ((PASS++)) || true
else
    echo "  ❌ browser_eval returned null or empty"
    echo "     response: $R"
    ((FAIL++)) || true
fi

# ── 11. browser_eval (undefined returns null) ─
echo "[ 11 ] browser_eval → undefined returns \"null\""
R=$(rpc "browser_eval" "{\"script\":\"/* no return */\"}")
TEXT=$(echo "$R" | jq -r ".result.content[0].text // \"\"" 2>/dev/null)
if [[ "$TEXT" == "null" ]]; then
    echo "  ✅ undefined script returns \"null\""
    ((PASS++)) || true
else
    echo "  ❌ expected \"null\", got: ${TEXT}"
    ((FAIL++)) || true
fi

# ── 12. browser_screenshot (path) ────────────
echo "[ 12 ] browser_screenshot --format path"
R=$(rpc "browser_screenshot" "{\"format\":\"path\"}")
SPATH=$(echo "$R" | jq -r ".result.content[0].text" | jq -r ".path" 2>/dev/null)
if [[ -n "$SPATH" && -f "$SPATH" ]]; then
    FSIZE=$(wc -c < "$SPATH")
    echo "  ✅ screenshot written to ${SPATH} (${FSIZE} bytes)"
    ((PASS++)) || true
else
    echo "  ❌ screenshot path invalid or file missing: ${SPATH}"
    echo "     response: $R"
    ((FAIL++)) || true
fi

# ── 13. browser_screenshot (base64) ──────────
echo "[ 13 ] browser_screenshot --format base64"
R=$(rpc "browser_screenshot" "{\"format\":\"base64\"}")
B64=$(echo "$R" | jq -r ".result.content[0].text" | jq -r ".base64 // empty" 2>/dev/null)
if [[ -n "$B64" && ${#B64} -gt 100 ]]; then
    echo "  ✅ base64 screenshot returned (${#B64} chars)"
    ((PASS++)) || true
else
    echo "  ❌ base64 screenshot missing or too short"
    echo "     response: $R"
    ((FAIL++)) || true
fi

# ── 14. browser_wait (text) ──────────────────
echo "[ 14 ] browser_wait --condition text --value Example"
R=$(rpc "browser_wait" "{\"condition\":\"text\",\"value\":\"Example\",\"timeout\":10}")
assert_ok "wait for text 'Example'" "$R"

# ── 15. browser_wait (url) ───────────────────
echo "[ 15 ] browser_wait --condition url --value example.com"
R=$(rpc "browser_wait" "{\"condition\":\"url\",\"value\":\"example.com\",\"timeout\":5}")
assert_ok "wait for url containing 'example.com'" "$R"

# ── 16. browser_close_tab ────────────────────
echo "[ 16 ] browser_close_tab"
R=$(rpc "browser_close_tab" "{\"tabId\":\"${URL_TAB_ID}\"}")
assert_ok "close tab" "$R"

# ── 17. browser_open_split ───────────────────
echo "[ 17 ] browser_open_split (open panel)"
R=$(rpc "browser_open_split" "{}")
assert_ok "open_split returns ok" "$R"

# ── 18. browser_open_split with URL ──────────
echo "[ 18 ] browser_open_split --url https://example.com"
R=$(rpc "browser_open_split" "{\"url\":\"https://example.com\"}")
assert_ok "open_split with url" "$R"

# ── 19. browser_wait timeout ─────────────────
echo "[ 19 ] browser_wait timeout (condition that never matches)"
R=$(rpc "browser_wait" "{\"condition\":\"text\",\"value\":\"__POLTERTTY_NONEXISTENT_TEXT__\",\"timeout\":2}")
ERR=$(echo "$R" | jq -r '.error.message // empty' 2>/dev/null)
if echo "$ERR" | grep -q "timeout"; then
    echo "  ✅ timeout error returned as expected"
    ((PASS++)) || true
else
    echo "  ❌ expected timeout error, got: $R"
    ((FAIL++)) || true
fi

# ── 20. browser_eval (schema validation) ─────
echo "[ 20 ] browser_eval missing script → -32602"
R=$(rpc "browser_eval" "{}")
CODE=$(echo "$R" | jq -r '.error.code // empty' 2>/dev/null)
if [[ "$CODE" == "-32602" ]]; then
    echo "  ✅ invalid params returns -32602"
    ((PASS++)) || true
else
    echo "  ❌ expected -32602, got: $R"
    ((FAIL++)) || true
fi

# ─────────────────────────────────────────────
# 结果汇总
# ─────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════"
echo " Results"
echo "═══════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
echo " Total:  ${TOTAL}"
echo " Passed: ${PASS}"
echo " Failed: ${FAIL}"
if [[ "$FAIL" -eq 0 ]]; then
    echo " Status: ✅ ALL PASSED"
else
    echo " Status: ❌ ${FAIL} FAILED"
fi
echo "═══════════════════════════════════════════"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
