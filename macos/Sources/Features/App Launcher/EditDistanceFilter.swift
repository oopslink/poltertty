// macos/Sources/Features/App Launcher/EditDistanceFilter.swift

enum EditDistanceFilter {
    /// Levenshtein 距离（标准 DP 矩阵）
    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                if a[i-1] == b[j-1] {
                    curr[j] = prev[j-1]
                } else {
                    curr[j] = 1 + min(prev[j], curr[j-1], prev[j-1])
                }
            }
            prev = curr
        }
        return prev[n]
    }

    /// 对 options 按相关性排序。query 为空时返回空数组。
    /// 同时对 title 和 subtitle 计算距离，取较小值（支持英文搜索中文标题）。
    /// contains 匹配的 option 距离减 3（最低 0）。
    /// 过滤有效距离超过 max(query.count, 3) 的结果。
    /// 返回前 8 条。
    static func rank(_ query: String, in options: [CommandOption]) -> [CommandOption] {
        guard !query.isEmpty else { return [] }

        let q = query.lowercased()
        let threshold = max(q.count, 3)

        return options
            .compactMap { option -> (CommandOption, Int)? in
                let title = option.title.lowercased()
                var dist = levenshteinDistance(q, title)
                var containsMatch = title.contains(q)

                // 同时检查 subtitle（支持英文 query 匹配中文标题的 subtitle）
                if let subtitle = option.subtitle?.lowercased() {
                    let subtitleDist = levenshteinDistance(q, subtitle)
                    if subtitleDist < dist { dist = subtitleDist }
                    if subtitle.contains(q) { containsMatch = true }
                }

                if containsMatch { dist = max(0, dist - 3) }
                guard dist <= threshold else { return nil }
                return (option, dist)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(8)
            .map { $0.0 }
    }
}
