// macos/Sources/Features/Terminal/ProcessTreeCwd.swift
import Foundation
import Darwin

/// 给定 shellPid，遍历进程树找到最前台子进程的 CWD。
/// 用于在 OSC 7 不可用时（如 Claude Code 运行期间）更新 status bar。
///
/// 算法：BFS 收集 shellPid 后代 → 找叶子节点（无子进程）
/// → 多叶子取最晚启动的（近似最前台，Claude Code 单进程场景完全准确）
/// → proc_pidinfo(PROC_PIDVNODEPATHINFO) 取 CWD
enum ProcessTreeCwd {

    /// 返回 shellPid 后代中最前台进程的 CWD。
    /// shellPid = 0 → nil；无后代 → fallback 到 shellPid 自身 CWD。
    static func foregroundCwd(shellPid: pid_t) -> String? {
        guard shellPid > 0 else { return nil }

        // ── 1. 拿到所有 PID ──────────────────────────────────────────────
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64) // 多分配防竞态
        let actual = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard actual > 0 else { return nil }

        // ── 2. 构建父→子映射，收集 shellPid 后代（BFS）────────────────────
        var childrenOf: [pid_t: [pid_t]] = [:]
        for i in 0..<Int(actual) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var info = proc_bsdshortinfo()
            let ret = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0,
                                   &info, Int32(MemoryLayout<proc_bsdshortinfo>.size))
            guard ret > 0 else { continue }   // ESRCH / EPERM → 跳过
            childrenOf[pid_t(info.pbsi_ppid), default: []].append(pid)
        }

        var descendants: Set<pid_t> = []
        var bfsQueue = childrenOf[shellPid] ?? []
        var head = 0
        while head < bfsQueue.count {
            let pid = bfsQueue[head]; head += 1
            descendants.insert(pid)
            if let children = childrenOf[pid] { bfsQueue.append(contentsOf: children) }
        }

        // ── 3. 找叶子（无子进程的后代）──────────────────────────────────
        let leaves = descendants.filter { childrenOf[$0] == nil || childrenOf[$0]!.isEmpty }

        // ── 4. 确定目标进程 ────────────────────────────────────────────
        let targetPid: pid_t
        if leaves.isEmpty {
            targetPid = shellPid          // fallback：后代已全部退出
        } else if leaves.count == 1 {
            targetPid = leaves.first!
        } else {
            // 多叶子：取 pbi_start_tvsec 最大的（最晚启动 ≈ 最前台）
            targetPid = leaves.max { startTime(of: $0) < startTime(of: $1) } ?? leaves.first!
        }

        // ── 5. 取 CWD ───────────────────────────────────────────────────
        return cwd(of: targetPid) ?? (targetPid != shellPid ? cwd(of: shellPid) : nil)
    }

    // MARK: - Helpers

    private static func startTime(of pid: pid_t) -> UInt64 {
        var info = proc_bsdinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0,
                               &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        return ret > 0 ? info.pbi_start_tvsec : 0
    }

    private static func cwd(of pid: pid_t) -> String? {
        var pathInfo = proc_vnodepathinfo()
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0,
                               &pathInfo, Int32(MemoryLayout<proc_vnodepathinfo>.size))
        guard ret > 0 else { return nil }
        // vip_path 是 C 固定长度数组，Swift 导入为元组，用 withUnsafeBytes 安全访问
        let s = withUnsafeBytes(of: pathInfo.pvi_cdir.vip_path) { rawBuf in
            rawBuf.withMemoryRebound(to: CChar.self) { buf in
                String(cString: buf.baseAddress!)
            }
        }
        return s.isEmpty ? nil : s
    }
}
