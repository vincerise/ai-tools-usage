import Foundation

/// Cursor 把对话存在 `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` 的 `cursorDiskKV` 表：
/// - `composerData:<composerId>`：会话元数据（createdAt、模型配置）
/// - `bubbleId:<composerId>:<bubbleId>`：单条消息，type 2 为助手回复，带 `tokenCount:{inputTokens,outputTokens}`
/// Cursor 不区分缓存 token，全部记入未缓存输入。
///
/// 项目路径是 **best-effort**：Cursor 的 schema 不公开，工作目录散落在 `workspaceIdentifier` /
/// `workspaceProjectDir` / `workspaceFolder` 几个可能的位置，不同版本写法还不一样。
/// 取不到就留空、归入「未归类」—— 不拿数据库路径或会话 id 去猜一个项目出来。
struct CursorProvider: UsageProvider {
    func scan(paths: [String]) -> [UsageRecord] {
        paths.flatMap(scanDatabase)
    }

    private func scanDatabase(_ path: String) -> [UsageRecord] {
        guard let db = SQLiteReader(path: path), db.hasTable("cursorDiskKV") else { return [] }

        var composerCreated: [String: Date] = [:]
        var composerModel: [String: String] = [:]
        var composerProject: [String: String] = [:]
        db.query("SELECT key, value FROM cursorDiskKV WHERE key LIKE 'composerData:%'") { stmt in
            let key = SQLiteReader.text(stmt, 0)
            guard let obj = SQLiteReader.json(stmt, 1) else { return }
            let id = String(key.dropFirst("composerData:".count))
            if let d = ParseUtil.date(from: obj["createdAt"]) { composerCreated[id] = d }
            if let m = Self.model(in: obj) { composerModel[id] = m }
            // composer 级的路径是这一整段对话的兜底；bubble 自己若带路径，以 bubble 为准
            if let p = Self.projectPath(in: obj) { composerProject[id] = p }
        }

        var records: [UsageRecord] = []
        db.query("SELECT key, value FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'") { stmt in
            let key = SQLiteReader.text(stmt, 0)
            let parts = key.split(separator: ":")
            guard parts.count >= 3, let obj = SQLiteReader.json(stmt, 1),
                  ParseUtil.int(obj["type"]) == 2,
                  let tc = obj["tokenCount"] as? [String: Any] else { return }
            let composerId = String(parts[1])
            let input = ParseUtil.int(tc["inputTokens"])
            let output = ParseUtil.int(tc["outputTokens"])
            guard input + output > 0 else { return }

            let timing = obj["timingInfo"] as? [String: Any]
            let ts = ParseUtil.date(from: timing?["clientRpcSendTime"])
                ?? ParseUtil.date(from: timing?["clientSettleTime"])
                ?? ParseUtil.date(from: obj["createdAt"])
                ?? composerCreated[composerId]
            guard let ts else { return }
            let model = Self.model(in: obj) ?? composerModel[composerId] ?? "cursor-unknown"
            let project = Self.projectPath(in: obj) ?? composerProject[composerId] ?? ""

            records.append(UsageRecord(provider: .cursor, sessionId: composerId, model: model, timestamp: ts,
                                       inputUncached: input, cacheRead: 0, cacheWrite: 0, output: output,
                                       projectCwd: project))
        }
        return records
    }

    private static func model(in obj: [String: Any]) -> String? {
        for key in ["modelInfo", "modelConfig"] {
            if let m = obj[key] as? [String: Any], let name = m["modelName"] as? String, !name.isEmpty { return name }
        }
        if let name = obj["modelName"] as? String, !name.isEmpty { return name }
        return nil
    }

    /// 按「最具体 → 最笼统」的顺序找工作目录。返回的是**原始值**，
    /// `file://` 与尾斜杠由 `ProjectResolver.normalize` 统一处理。
    ///
    /// `workspaceIdentifier.uri` 可能是 URI 字符串，也可能是一个 `{fsPath, path}` 对象，
    /// 两种都收；`workspaceIdentifier.fsPath` 是某些版本直接拍平后的写法。
    static func projectPath(in obj: [String: Any]) -> String? {
        func pick(_ value: Any?) -> String? {
            guard let s = value as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        if let p = pick(obj["workspaceProjectDir"]) { return p }
        if let wi = obj["workspaceIdentifier"] as? [String: Any] {
            if let config = wi["configPath"] as? [String: Any], let p = pick(config["fsPath"]) { return p }
            if let p = pick(wi["configPath"]) { return p }
            if let uri = wi["uri"] as? [String: Any], let p = pick(uri["fsPath"]) { return p }
            if let p = pick(wi["uri"]) { return p }
            if let p = pick(wi["fsPath"]) { return p }
        }
        if let p = pick(obj["workspaceFolder"]) { return p }
        if let p = pick(obj["cwd"]) { return p }
        return nil
    }
}
