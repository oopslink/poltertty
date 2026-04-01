-- macos/Resources/yazi-config/plugins/git-diff.yazi/init.lua
local M = {}

function M:peek()
    local url = tostring(self.file.url)

    local status = Command("git")
        :args({ "status", "--porcelain", "--", url })
        :stdout(Command.PIPED)
        :stderr(Command.NULL)
        :output()

    if not status or #status.stdout == 0 then
        require("code"):peek(self)
        return
    end

    local diff = Command("git")
        :args({ "diff", "HEAD", "--", url })
        :stdout(Command.PIPED)
        :stderr(Command.NULL)
        :output()

    if not diff or #diff.stdout == 0 then
        require("code"):peek(self)
        return
    end

    local delta_path = os.getenv("YAZI_DELTA_PATH") or "delta"
    local colored = Command(delta_path)
        :args({ "--paging=never", "--width=" .. tostring(self.area.w) })
        :stdin(Command.PIPED)
        :stdout(Command.PIPED)
        :stderr(Command.NULL)
        :spawn()

    if colored then
        colored:write_all(diff.stdout)
        colored:flush()
        local output = colored:wait_with_output()
        if output and #output.stdout > 0 then
            ya.preview_widgets(self, { ui.Text.parse(output.stdout) })
            return
        end
    end

    ya.preview_widgets(self, { ui.Text(diff.stdout) })
end

function M:seek(units)
    require("code"):seek(units)
end

return M
