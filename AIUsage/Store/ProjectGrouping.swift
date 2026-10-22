import Foundation

/// 项目怎么归组。两种口径对应同一个原始数据的两列（见 `AggregateRow.cwd` / `.gitRoot`），
/// 切换时只重算内存里的聚合行，**不重扫本地日志** —— 这正是两列都要同步的原因。
enum ProjectGrouping: String, CaseIterable, Identifiable {
    /// 同一仓库的子目录合并成一个项目。没有 `.git` 的目录回退到工作目录本身。
    case gitRoot
    /// 会话实际所在目录，原样分组（同一仓库的根与子目录会拆成两个项目）。
    case workingDirectory

    var id: Self { self }

    var label: String {
        switch self {
        case .gitRoot: return "Git 仓库根目录"
        case .workingDirectory: return "会话工作目录"
        }
    }

    /// 导出与文件名用的 ASCII 标记（导出 JSON 的 `meta.project_grouping` 也用它）
    var fileTag: String {
        switch self {
        case .gitRoot: return "gitRoot"
        case .workingDirectory: return "workingDirectory"
        }
    }

    /// 键名是**有用户数据挂在上面的事实来源**，不许随手改（改它等于清空所有人这个设置）
    static let key = "projects.grouping.v1"

    /// 从配置域读。读不到或值不认得都回退到 `.gitRoot` ——
    /// plist 可以手改，界面上落在一个无效档位比落在默认档更糟。
    static func stored(in defaults: UserDefaults) -> ProjectGrouping {
        guard let raw = defaults.string(forKey: key), let v = ProjectGrouping(rawValue: raw) else {
            return .gitRoot
        }
        return v
    }

    static func store(_ grouping: ProjectGrouping, in defaults: UserDefaults) {
        defaults.set(grouping.rawValue, forKey: key)
    }

    /// 一条聚合记录归到哪个项目。三种情况：
    /// - Git 根口径：有仓库根就用它，没有就回退到工作目录本身（无 `.git` 的目录也要能分组）
    /// - 会话目录口径：工作目录原样
    /// - 数据源没给路径：空串，调用方标「未归类」
    func key(cwd: String, gitRoot: String) -> String {
        switch self {
        case .gitRoot: return gitRoot.isEmpty ? cwd : gitRoot
        case .workingDirectory: return cwd
        }
    }
}
