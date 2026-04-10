-- Git diff previewer with delta coloring for yazi >= 26.x
-- Shows colored diff for modified files, falls back to code preview otherwise.
local M = {}

function M:peek(job)
    local path = tostring(job.file.path)

    local status = Command("git")
        :arg({ "status", "--porcelain", "--", path })
        :stdout(Command.PIPED)
        :stderr(Command.NULL)
        :output()

    if not status or #status.stdout == 0 then
        return require("code"):peek(job)
    end

    local diff = Command("git")
        :arg({ "diff", "HEAD", "--", path })
        :stdout(Command.PIPED)
        :stderr(Command.NULL)
        :output()

    if not diff or #diff.stdout == 0 then
        return require("code"):peek(job)
    end

    local delta_path = os.getenv("YAZI_DELTA_PATH") or "delta"
    local child = Command(delta_path)
        :arg({ "--paging=never", "--width=" .. tostring(job.area.w) })
        :stdin(Command.PIPED)
        :stdout(Command.PIPED)
        :stderr(Command.NULL)
        :spawn()

    if child then
        child:write_all(diff.stdout)
        child:flush()
        local output = child:wait_with_output()
        if output and #output.stdout > 0 then
            ya.preview_widget(job, ui.Text.parse(output.stdout):area(job.area))
            return
        end
    end

    ya.preview_widget(job, ui.Text(diff.stdout):area(job.area))
end

function M:seek(job)
    require("code"):seek(job)
end

return M
