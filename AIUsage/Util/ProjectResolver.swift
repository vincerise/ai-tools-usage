import Foundation

/// 项目路径的规范化、Git 仓库根解析与显示名消歧。
///
/// 这里只做**纯函数 + 文件系统只读探测**：不缓存到全局（`git init` 之后全局缓存会永不失效），
/// 也不写任何东西。`enrich` 在一次扫描里用局部 memo 摊掉重复探测。
enum ProjectResolver {
    /// 没有工作目录的数据归到这里。它不是一个项目 —— 看板单独放在页脚、导出 `project_path` 留空。
    static let unassignedLabel = "未归类"

    // MARK: 规范化

    /// 把各数据源给的路径统一成绝对路径。
    ///
    /// - 去首尾空白、展开 `~`、处理 `file://` URI（Cursor 的 workspace uri 可能是这种）
    /// - `standardizedFileURL` 只折叠 `.` / `..` 与多余的斜杠，**不解析 symlink**：
    ///   会话里记录的 cwd 就是用户看到的那条路径，realpath 会把 `/tmp/x` 和 `/private/tmp/x`
    ///   合并成一个项目，也会多出每文件一次的系统调用。宁可把两种写法当成两个项目。
    /// - 相对路径与空串都返回空串 —— 空串是「没有路径」，不是根目录。
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        if s.lowercased().hasPrefix("file://") {
            if let url = URL(string: s), url.isFileURL {
                s = url.path
            } else {
                // URL(string:) 对带空格 / 未转义字符的串可能失败，退回手动去掉 scheme
                s = String(s.dropFirst("file://".count))
                s = s.removingPercentEncoding ?? s
            }
        }

        s = (s as NSString).expandingTildeInPath
        guard s.hasPrefix("/") else { return "" }

        let path = URL(fileURLWithPath: s).standardizedFileURL.path
        // 根目录保留 "/"，其余去掉尾斜杠（同一目录的两种写法必须落进同一个桶）
        if path.count > 1, path.hasSuffix("/") { return String(path.dropLast()) }
        return path
    }

    // MARK: Git 仓库根

    /// 从 cwd 逐级向上找 `.git`，返回第一个命中的目录；找不到返回空串。
    ///
    /// `.git` 是目录（普通仓库）或文件（worktree / submodule）都算 ——
    /// 判据只是「这一级存在 `.git`」，不进去读内容。
    static func gitRoot(for cwd: String) -> String {
        let path = normalize(cwd)
        guard !path.isEmpty else { return "" }

        var url = URL(fileURLWithPath: path)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return url.path
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }   // 防御：理论上不会发生
            url = parent
        }
        return FileManager.default.fileExists(atPath: "/.git") ? "/" : ""
    }

    // MARK: 扫描后补全

    /// 给一批刚扫出来的记录补 `projectGitRoot`（并顺手规范化 `projectCwd`）。
    ///
    /// 演示模式原样返回：DemoData 里的 `gitRoot` 是编好的，去 stat 作者的磁盘既慢又不确定。
    ///
    /// memo 只活这一次调用：同一批记录里几十条共享同一个 cwd 是常态，
    /// 每个唯一目录只向上探测一次；下次刷新重新探测，`git init` / 删 `.git` 都能立刻反映出来。
    static func enrich(_ records: [UsageRecord]) -> [UsageRecord] {
        guard !DemoRuntime.isActive else { return records }

        var memo: [String: String] = [:]
        return records.map { record in
            let cwd = normalize(record.projectCwd)
            guard !cwd.isEmpty else { return record }
            let root: String
            if let hit = memo[cwd] {
                root = hit
            } else {
                root = gitRoot(for: cwd)
                memo[cwd] = root
            }
            if cwd == record.projectCwd && root == record.projectGitRoot { return record }
            return record.with(projectCwd: cwd, projectGitRoot: root)
        }
    }

    // MARK: 显示名

    /// 给每个分组键起一个**在本次范围内唯一**的显示名。
    ///
    /// 默认取末级目录名；重名时逐级加上父目录（`a/foo`、`b/foo`），仍然重名就用完整路径。
    /// 与「未归类」撞名时也走消歧 —— 一个真叫「未归类」的目录混进页脚的未归类里，
    /// 读者会以为那是同一堆没路径的数据，这句话就说不清了。
    ///
    /// 空键不在这里处理：调用方负责把它显示成 `unassignedLabel`。
    static func labels(for keys: some Sequence<String>) -> [String: String] {
        let all = Set(keys.filter { !$0.isEmpty })
        var components: [String: [String]] = [:]
        var maxDepth = 1
        for key in all {
            let parts = pathComponents(key)
            components[key] = parts
            maxDepth = max(maxDepth, parts.count)
        }

        var out: [String: String] = [:]
        var pending = all
        var depth = 1
        while !pending.isEmpty {
            var byLabel: [String: [String]] = [:]
            for key in pending {
                let parts = components[key] ?? []
                let n = min(depth, max(1, parts.count))
                let candidate = parts.isEmpty ? key : parts.suffix(n).joined(separator: "/")
                byLabel[candidate, default: []].append(key)
            }
            for (label, grouped) in byLabel where grouped.count == 1 && label != unassignedLabel {
                out[grouped[0]] = label
                pending.remove(grouped[0])
            }
            if pending.isEmpty { break }
            if depth >= maxDepth {
                // 一路同名到底，或者候选名与「未归类」始终相同：完整路径是唯一不会误解的写法
                for key in pending { out[key] = key }
                break
            }
            depth += 1
        }
        return out
    }

    private static func pathComponents(_ key: String) -> [String] {
        var parts = key.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if let last = parts.last, last.hasSuffix(".code-workspace") {
            let stem = String(last.dropLast(".code-workspace".count))
            if !stem.isEmpty { parts[parts.count - 1] = stem }
        }
        return parts
    }

    /// 界面上的短路径：本机 home 换成 `~`。演示数据里的 `/Users/you/...` 原样保留 ——
    /// 那是编出来的路径，不能因为跑在作者机器上就被替换掉前缀。
    static func displayPath(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        if DemoRuntime.isActive { return path }
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }
        return path
    }
}
