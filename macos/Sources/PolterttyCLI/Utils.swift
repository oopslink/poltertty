// macos/Sources/PolterttyCLI/Utils.swift
import Foundation

/// 从命令行参数中提取指定 flag 的值
func extractArg(_ flag: String, from args: [String]) -> String? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

/// 同步执行 HTTP 请求，返回 (data, response)；超时默认 5 秒
func syncRequest(_ request: URLRequest, timeout: TimeInterval = 5) -> (Data?, HTTPURLResponse?) {
    let semaphore = DispatchSemaphore(value: 0)
    var resultData: Data?
    var resultResponse: HTTPURLResponse?

    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = timeout
    config.timeoutIntervalForResource = timeout
    let session = URLSession(configuration: config)

    let task = session.dataTask(with: request) { data, response, _ in
        resultData = data
        resultResponse = response as? HTTPURLResponse
        semaphore.signal()
    }
    task.resume()
    semaphore.wait()
    return (resultData, resultResponse)
}
