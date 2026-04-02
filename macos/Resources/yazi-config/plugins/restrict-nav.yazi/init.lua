-- macos/Resources/yazi-config/plugins/restrict-nav.yazi/init.lua
-- 拦截 h 键向上导航，防止离开 YAZI_ROOT_DIR（workspace 根目录）。
-- 默认布局 ratio=[0,1,3] 隐藏左侧父目录面板，使 workspace 视觉上即为根目录。

local get_cwd = ya.sync(function(_)
    return tostring(cx.active.current.cwd)
end)

local M = {}

function M:entry(_, _)
    local root = os.getenv("YAZI_ROOT_DIR") or ""
    if root == "" then
        ya.emit("leave", {})
        return
    end

    root = root:gsub("/+$", "")

    local cwd = get_cwd()
    local parent = cwd:match("^(.+)/[^/]+$") or cwd

    -- 仅当父目录是 root 或在 root 内部时才允许向上导航
    if parent == root or parent:sub(1, #root + 1) == root .. "/" then
        ya.emit("leave", {})
    end
    -- 否则静默阻止：已在 workspace 根目录
end

return M
