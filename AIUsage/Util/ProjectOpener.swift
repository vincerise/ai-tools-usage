import AppKit

/// 「在访达中打开项目」。
///
/// 项目路径来自会话日志，可能已经被删除、移动，或者根本属于另一台设备 ——
/// 同步档案里只有路径，没有目录本身。这些情况**不能静默什么都不发生**：
/// 用户点了一下，总得知道为什么没打开。所以所有失败都收敛成一个带说明的 `Failure`，
/// 由界面弹一句提示，而不是假装成功。
enum ProjectOpener {
    enum Failure: Error, Equatable {
        /// 空路径：未归类，或数据源没有提供工作目录
        case unassigned
        /// 磁盘上找不到这个路径
        case missing(String)
        /// 路径存在，但系统没有接住这次打开
        case cannotOpen(String)
    }

    /// 只做校验，不碰访达 —— 自测要能在不弹窗、不打开访达的情况下钉住这些判断。
    ///
    /// 规范化沿用 `ProjectResolver.normalize`：尾斜杠、`~`、`file://` 与分组时是同一套口径，
    /// 否则会出现「看板上是 A、打开时找的是 A/」这种对不上的情况。
    static func resolve(path: String) -> Result<URL, Failure> {
        let normalized = ProjectResolver.normalize(path)
        guard !normalized.isEmpty else { return .failure(.unassigned) }
        let url = URL(fileURLWithPath: normalized)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.missing(url.path))
        }
        return .success(url)
    }

    /// 目录直接在访达里打开；路径其实指向文件时（Cursor 的 `.code-workspace` 这类），
    /// 在其所在目录里选中它 —— 对文件调 `open` 会交给关联的编辑器，那不是「在访达中打开」。
    ///
    /// 返回 nil 表示已经交给访达；否则是给用户看的原因。
    @discardableResult
    static func open(path: String) -> Failure? {
        switch resolve(path: path) {
        case .failure(let failure):
            return failure
        case .success(let url):
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                return NSWorkspace.shared.open(url) ? nil : .cannotOpen(url.path)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return nil
        }
    }

    /// 界面入口：失败时弹一句说明（与导出失败用的是同一种提示）。
    static func openWithFeedback(path: String) {
        guard let failure = open(path: path) else { return }
        let alert = NSAlert()
        if case .unassigned = failure {
            alert.alertStyle = .informational
        } else {
            alert.alertStyle = .warning
        }
        alert.messageText = title(for: failure)
        alert.informativeText = message(for: failure)
        alert.runModal()
    }

    static func title(for failure: Failure) -> String {
        switch failure {
        case .unassigned: return "这个项目没有路径"
        case .missing, .cannotOpen: return "无法在访达中打开项目"
        }
    }

    static func message(for failure: Failure) -> String {
        switch failure {
        case .unassigned:
            return "「未归类」的用量来自没有提供工作目录的数据源（Qoder、加密数据源，或旧版本 App 写的设备档案），没有可以在访达中打开的位置。"
        case .missing(let path):
            return "找不到 \(ProjectResolver.displayPath(path))。它可能已经被删除或移动，也可能这条用量来自另一台设备 —— 同步档案里只有路径，没有目录本身。"
        case .cannotOpen(let path):
            return "访达没有打开 \(ProjectResolver.displayPath(path))。"
        }
    }
}
