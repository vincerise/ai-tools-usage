import Foundation

/// 手动把两个项目并成一个：「旧路径 → 新路径」。
///
/// 目录改名或搬家之后，按路径分组的账会裂成两行 —— 旧路径的 session 不会自己跟到新路径上。
/// 这里存一组**路径前缀替换**：分组前先把行里的 `cwd` / `gitRoot` 改写一遍，
/// 两段历史就落进同一个桶。
///
/// 它不是数据修正：原始日志、设备档案一个字节都不动，只影响本机的分组与导出。
/// 因此也不需要重扫 —— 改的是内存里那份 `AggregateRow` 的读法，与切换分组口径同一类操作。
struct ProjectAlias: Codable, Equatable, Hashable, Identifiable {
    let from: String
    let to: String

    var id: String { "\(from)→\(to)" }
}

enum ProjectAliases {
    /// 键名带版本：以后要换成「带显示名的别名」时可以整份换代，旧值自然回退为空。
    static let key = "projects.aliases.v1"

    // MARK: 读写

    static func stored(in defaults: UserDefaults) -> [ProjectAlias] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ProjectAlias].self, from: data) else { return [] }

        // 存进来的东西也过一遍规范化：手改过 plist、或旧版本留下的相对路径 / 尾斜杠，
        // 不能原样带进分组 —— 否则「合并了却没生效」会变成一处查不出来的怪事。
        let cleaned = decoded.compactMap { alias -> ProjectAlias? in
            let from = ProjectResolver.normalize(alias.from)
            let to = ProjectResolver.normalize(alias.to)
            guard !from.isEmpty, !to.isEmpty, from != to else { return nil }
            return ProjectAlias(from: from, to: to)
        }
        // 同一个 from 只留第一条：两条同源映射谁生效取决于遍历顺序，不能靠运气。
        var seen = Set<String>()
        return cleaned.filter { seen.insert($0.from).inserted }
    }

    static func store(_ aliases: [ProjectAlias], in defaults: UserDefaults) {
        guard !aliases.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(aliases) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: 改写

    /// 把路径换成别名目标。按**最长前缀**匹配，支持链式（A→B、B→C），环由 `seen` 兜底。
    ///
    /// 前缀必须落在目录边界上：`/a` 不能命中 `/ab`，否则 `/Users/you/work/app` 会把
    /// `/Users/you/work/application` 也一起吞掉。
    static func rewrite(_ path: String, using aliases: [ProjectAlias]) -> String {
        guard !path.isEmpty, !aliases.isEmpty else { return path }
        var current = path
        var seen: Set<String> = [current]
        // 最多走 alias 条数 + 1 步；正常链远短于此，环会被 seen 提前拦住
        for _ in 0...aliases.count {
            guard let alias = aliases
                .filter({ $0.matches(current) })
                .max(by: { $0.from.count < $1.from.count }) else { break }
            let next = alias.to + current.dropFirst(alias.from.count)
            guard seen.insert(next).inserted else { break }
            current = next
        }
        return current
    }

    /// 项目分组键：先把两列路径都改写，再交给当前口径折成一个。
    /// `recompute` 与「所有历史项目」列表共用这一处，避免各算各的。
    static func projectKey(cwd: String, gitRoot: String, grouping: ProjectGrouping,
                           aliases: [ProjectAlias]) -> String {
        grouping.key(cwd: rewrite(cwd, using: aliases), gitRoot: rewrite(gitRoot, using: aliases))
    }
}

private extension ProjectAlias {
    func matches(_ path: String) -> Bool {
        if from == "/" { return path.hasPrefix("/") }
        return path == from || path.hasPrefix(from + "/")
    }
}
