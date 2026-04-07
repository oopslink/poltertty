// macos/PolterttyCLI/Commands/BrowserCommand.swift
import Foundation

/// poltertty-cli browser <action> [options]
///
/// Actions:
///   snapshot   获取页面可交互元素快照（ARIA 树 + 编号引用）
///   navigate   导航到 URL
///   click      点击元素
///   fill       填充输入框
///   eval       执行任意 JavaScript
///   wait       等待条件
///   screenshot 截图
///   get-text   获取元素或页面文字
///   open       打开浏览器面板（可选导航）
///   new-tab    新建 tab
///   close-tab  关闭 tab
///   focus-tab  切换 active tab
///   list-tabs  列出所有 tab
///
/// 通用选项（所有 action 均支持）：
///   --port <port>           Ctrl API 端口（必填）
///   --workspace-id <uuid>   目标 workspace UUID（可选）
///   --tab-id <uuid>         目标 browser tab UUID（可选）
///   --timeout <secs>        超时秒数（browser_wait 专用，默认 10）

enum BrowserCommand {
    static func run(_ args: [String]) {
        guard let action = args.first else {
            fputs(usage, stderr); exit(1)
        }
        let restArgs = Array(args.dropFirst())

        guard let portStr = extractArg("--port", from: restArgs),
              let port = UInt16(portStr) else {
            fputs("Error: --port is required\n", stderr); exit(1)
        }

        // 构建 MCP 工具调用参数
        var toolName: String
        var toolArgs: [String: Any] = [:]

        if let wsId = extractArg("--workspace-id", from: restArgs) { toolArgs["workspaceId"] = wsId }
        if let tabId = extractArg("--tab-id", from: restArgs)       { toolArgs["tabId"] = tabId }

        switch action {
        case "snapshot":
            toolName = "browser_snapshot"

        case "navigate":
            guard let url = extractArg("--url", from: restArgs) else {
                fputs("Error: navigate requires --url\n", stderr); exit(1)
            }
            toolName = "browser_navigate"
            toolArgs["url"] = url

        case "click":
            if let ref = extractArg("--ref", from: restArgs)           { toolArgs["ref"] = ref }
            if let sel = extractArg("--selector", from: restArgs)      { toolArgs["selector"] = sel }
            guard toolArgs["ref"] != nil || toolArgs["selector"] != nil else {
                fputs("Error: click requires --ref or --selector\n", stderr); exit(1)
            }
            toolName = "browser_click"

        case "fill":
            if let ref = extractArg("--ref", from: restArgs)           { toolArgs["ref"] = ref }
            if let sel = extractArg("--selector", from: restArgs)      { toolArgs["selector"] = sel }
            guard toolArgs["ref"] != nil || toolArgs["selector"] != nil else {
                fputs("Error: fill requires --ref or --selector\n", stderr); exit(1)
            }
            guard let value = extractArg("--value", from: restArgs) else {
                fputs("Error: fill requires --value\n", stderr); exit(1)
            }
            toolName = "browser_fill"
            toolArgs["value"] = value

        case "eval":
            guard let script = extractArg("--script", from: restArgs) else {
                fputs("Error: eval requires --script\n", stderr); exit(1)
            }
            toolName = "browser_eval"
            toolArgs["script"] = script

        case "wait":
            guard let condition = extractArg("--condition", from: restArgs) else {
                fputs("Error: wait requires --condition (url|selector|text|load)\n", stderr); exit(1)
            }
            toolName = "browser_wait"
            toolArgs["condition"] = condition
            if let value = extractArg("--value", from: restArgs)       { toolArgs["value"] = value }
            if let timeout = extractArg("--timeout", from: restArgs),
               let t = Double(timeout) { toolArgs["timeout"] = t }

        case "screenshot":
            toolName = "browser_screenshot"
            if let fmt = extractArg("--format", from: restArgs)        { toolArgs["format"] = fmt }

        case "get-text":
            toolName = "browser_get_text"
            if let ref = extractArg("--ref", from: restArgs)           { toolArgs["ref"] = ref }
            if let sel = extractArg("--selector", from: restArgs)      { toolArgs["selector"] = sel }

        case "open":
            toolName = "browser_open_split"
            if let url = extractArg("--url", from: restArgs)           { toolArgs["url"] = url }

        case "new-tab":
            toolName = "browser_new_tab"
            if let url = extractArg("--url", from: restArgs)           { toolArgs["url"] = url }

        case "close-tab":
            guard let tabId = toolArgs["tabId"] as? String else {
                fputs("Error: close-tab requires --tab-id\n", stderr); exit(1)
            }
            _ = tabId
            toolName = "browser_close_tab"

        case "focus-tab":
            guard toolArgs["tabId"] != nil else {
                fputs("Error: focus-tab requires --tab-id\n", stderr); exit(1)
            }
            toolName = "browser_focus_tab"

        case "list-tabs":
            toolName = "browser_list_tabs"

        default:
            fputs("Error: unknown action '\(action)'\n\(usage)", stderr); exit(1)
        }

        // 发送 JSON-RPC 2.0 工具调用
        let rpcBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": ["name": toolName, "arguments": toolArgs]
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: rpcBody) else {
            fputs("Error: failed to serialize request\n", stderr); exit(1)
        }

        let url = URL(string: "http://localhost:\(port)/v1/mcp")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // browser_wait 可能耗时较长，使用更长超时
        let timeoutSec = (toolArgs["timeout"] as? Double).map { $0 + 2 } ?? 15.0
        let (data, response) = syncRequest(request, timeout: timeoutSec)

        guard let status = response?.statusCode, (200..<300).contains(status) else {
            fputs("Error: HTTP \(response?.statusCode ?? 0)\n", stderr); exit(1)
        }

        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fputs("Error: invalid response\n", stderr); exit(1)
        }

        // 提取 result.content[0].text 并打印
        if let result = json["result"] as? [String: Any],
           let content = result["content"] as? [[String: Any]],
           let text = content.first?["text"] as? String {
            print(text)
            exit(0)
        }

        // 打印错误信息
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            fputs("Error: \(message)\n", stderr); exit(1)
        }

        fputs("Error: unexpected response format\n", stderr); exit(1)
    }

    private static let usage = """
    Usage: poltertty-cli browser <action> --port <port> [options]

    Actions:
      snapshot                 获取页面可交互元素快照
      navigate --url <url>     导航到 URL
      click --ref <ref>        点击元素（--ref 或 --selector）
      fill --ref <ref> --value <val>  填充输入框
      eval --script <js>       执行 JavaScript
      wait --condition <cond>  等待条件 (url/selector/text/load)
      screenshot               截图
      get-text                 获取文字
      open [--url <url>]       打开浏览器面板
      new-tab [--url <url>]    新建 tab
      close-tab --tab-id <id>  关闭 tab
      focus-tab --tab-id <id>  切换 active tab
      list-tabs                列出所有 tab

    通用选项:
      --port <port>            Ctrl API 端口（必填）
      --workspace-id <uuid>    目标 workspace UUID（可选）
      --tab-id <uuid>          目标 browser tab UUID（可选）

    """
}
