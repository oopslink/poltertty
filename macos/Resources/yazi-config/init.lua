-- 启动时将 YAZI_ID 写入临时文件，供 YaziSurfaceStore.cdToDirectory 读取
local ws_id = os.getenv("POLTERTTY_WS_ID") or ""
local yazi_id = os.getenv("YAZI_ID") or ""
if ws_id ~= "" and yazi_id ~= "" then
    local f = io.open("/tmp/poltertty-yazi-" .. ws_id .. ".id", "w")
    if f then
        f:write(yazi_id)
        f:close()
    end
end
