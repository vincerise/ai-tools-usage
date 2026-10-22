import Foundation
import SwiftUI

/// 一次 LLM 请求的 token 用量，已跨工具归一化。
/// `inputUncached` 不含缓存读/写（OpenAI 的 input_tokens 含 cached，解析时已扣除）。
/// 对于本地只能拿到会话、拿不到 token 的工具（数据加密），允许 total == 0 的"仅会话"记录。
struct UsageRecord: Hashable, Codable {
    let provider: ProviderKind
    let sessionId: String
    let model: String
    let timestamp: Date
    let inputUncached: Int
    let cacheRead: Int
    let cacheWrite: Int
    let output: Int
    /// 这条记录所属会话的工作目录，由各数据源自己的会话元数据给出。
    /// **空串是如实表达「这个数据源没给路径」**，聚合与界面上归入「未归类」——
    /// 不能拿扫描路径、也不能拿会话文件名去猜一个项目出来。
    let projectCwd: String
    /// 从 `projectCwd` 逐级向上找到的 Git 仓库根（含 `.git` 的那一级）。
    /// 没有 `.git` 时为空串，按「Git 仓库根目录」分组时会回退到 `projectCwd`。
    let projectGitRoot: String

    var total: Int { inputUncached + cacheRead + cacheWrite + output }

    /// 两个项目字段放最后并给默认值：现有解析器的调用点一处都不用改，
    /// 只有真正拿得到工作目录的数据源才显式传。
    init(provider: ProviderKind, sessionId: String, model: String, timestamp: Date,
         inputUncached: Int, cacheRead: Int, cacheWrite: Int, output: Int,
         projectCwd: String = "", projectGitRoot: String = "") {
        self.provider = provider
        self.sessionId = sessionId
        self.model = model
        self.timestamp = timestamp
        self.inputUncached = inputUncached
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.output = output
        self.projectCwd = projectCwd
        self.projectGitRoot = projectGitRoot
    }

    enum CodingKeys: String, CodingKey {
        case provider, sessionId, model, timestamp
        case inputUncached, cacheRead, cacheWrite, output
        case projectCwd, projectGitRoot
    }

    func with(model: String) -> UsageRecord {
        UsageRecord(provider: provider, sessionId: sessionId, model: model, timestamp: timestamp,
                    inputUncached: inputUncached, cacheRead: cacheRead, cacheWrite: cacheWrite, output: output,
                    projectCwd: projectCwd, projectGitRoot: projectGitRoot)
    }

    func with(projectCwd: String, projectGitRoot: String) -> UsageRecord {
        UsageRecord(provider: provider, sessionId: sessionId, model: model, timestamp: timestamp,
                    inputUncached: inputUncached, cacheRead: cacheRead, cacheWrite: cacheWrite, output: output,
                    projectCwd: projectCwd, projectGitRoot: projectGitRoot)
    }
}

extension UsageRecord {
    /// 手写解码只为一件事：**旧缓存文件里没有 `projectCwd` / `projectGitRoot`**。
    ///
    /// `ScanCache` 与 `DevinCache` 都是按文件键的整条记录缓存，升级后第一次读到的仍是
    /// 上一版写下的 JSON。缺字段当空串而不是解析失败：升级不该让用户重扫全部日志
    /// （Devin 那份库有 2 GB），而空串在界面上就是如实的「未归类」。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decode(ProviderKind.self, forKey: .provider)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        model = try c.decode(String.self, forKey: .model)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        inputUncached = try c.decode(Int.self, forKey: .inputUncached)
        cacheRead = try c.decode(Int.self, forKey: .cacheRead)
        cacheWrite = try c.decode(Int.self, forKey: .cacheWrite)
        output = try c.decode(Int.self, forKey: .output)
        projectCwd = try c.decodeIfPresent(String.self, forKey: .projectCwd) ?? ""
        projectGitRoot = try c.decodeIfPresent(String.self, forKey: .projectGitRoot) ?? ""
    }
}

/// UI 上的"环境"。Codex Desktop/IDE 与 Codex CLI 共用数据源但分开展示。
enum ProviderKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case codex, codexCLI, claudeCode, devin, cursor, windsurf, antigravity, qoder, trae, codebuddy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .codexCLI: return "Codex CLI"
        case .claudeCode: return "Claude Code"
        case .devin: return "Devin"
        case .cursor: return "Cursor"
        case .windsurf: return "Windsurf"
        case .antigravity: return "Antigravity"
        case .qoder: return "Qoder"
        case .trae: return "TRAE"
        case .codebuddy: return "CodeBuddy"
        }
    }

    var symbol: String {
        switch self {
        case .codex: return "circle.hexagongrid"
        case .codexCLI: return "terminal"
        case .claudeCode: return "sparkle"
        case .devin: return "brain"
        case .cursor: return "cursorarrow.rays"
        case .windsurf: return "wind"
        case .antigravity: return "arrow.up.circle"
        case .qoder: return "q.circle"
        case .trae: return "t.circle"
        case .codebuddy: return "person.2"
        }
    }

    var source: SourceKind {
        switch self {
        case .codex, .codexCLI: return .codex
        case .claudeCode: return .claudeCode
        case .devin: return .devin
        case .cursor: return .cursor
        case .windsurf: return .windsurf
        case .antigravity: return .antigravity
        case .qoder: return .qoder
        case .trae: return .trae
        case .codebuddy: return .codebuddy
        }
    }
}

/// 数据源在本地能提供的统计粒度
enum SourceCapability {
    /// 每次请求的 token 明细，可计费
    case tokens
    /// 本地会话数据加密或不含 token，只能统计会话数与活跃日期
    case sessionsOnly
    /// 本地无可读数据
    case unavailable

    var label: String {
        switch self {
        case .tokens: return "Token 明细 + 费用"
        case .sessionsOnly: return "仅会话数（本地数据不含 token）"
        case .unavailable: return "本地数据不可读"
        }
    }
}

/// 磁盘上的一个数据源，可在设置中配置路径与开关。
enum SourceKind: String, CaseIterable, Codable, Identifiable {
    case claudeCode, codex, devin, cursor, qoder, codebuddy, windsurf, antigravity, trae

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex（Desktop / IDE / CLI）"
        case .devin: return "Devin"
        case .cursor: return "Cursor"
        case .qoder: return "Qoder"
        case .codebuddy: return "CodeBuddy Code"
        case .windsurf: return "Windsurf"
        case .antigravity: return "Antigravity"
        case .trae: return "TRAE"
        }
    }

    var capability: SourceCapability {
        switch self {
        case .claudeCode, .codex, .devin, .cursor, .qoder, .codebuddy: return .tokens
        case .windsurf, .antigravity: return .sessionsOnly
        case .trae: return .unavailable
        }
    }

    var pathHint: String {
        switch self {
        case .claudeCode: return "包含 <project>/<session>.jsonl 的目录"
        case .codex: return "包含 rollout-*.jsonl 的目录（递归扫描）"
        case .devin: return "sessions.db 文件路径"
        case .cursor: return "Cursor 的 globalStorage/state.vscdb 文件路径"
        case .qoder: return "Qoder 的 SharedClientCache/cache/db/local.db 文件路径"
        case .codebuddy: return "包含 <project>/<session>.jsonl 的目录（与 Claude Code 同格式）"
        case .windsurf: return "cascade 会话目录（*.pb，本地加密，仅统计会话数）"
        case .antigravity: return "conversations 目录（*.pb，本地加密，仅统计会话数）"
        case .trae: return "TRAE 本地库为 SQLCipher 加密，暂无法读取"
        }
    }

    var defaultPaths: [String] {
        let home = NSHomeDirectory()
        let appSupport = "\(home)/Library/Application Support"
        switch self {
        case .claudeCode: return ["\(home)/.claude/projects", "\(home)/.config/claude/projects"]
        case .codex: return ["\(home)/.codex/sessions", "\(home)/.codex/archived_sessions"]
        case .devin: return ["\(home)/.local/share/devin/cli/sessions.db"]
        case .cursor: return ["\(appSupport)/Cursor/User/globalStorage/state.vscdb"]
        case .qoder: return ["\(appSupport)/Qoder/SharedClientCache/cache/db/local.db", "\(home)/.qoder/shared_client/cache/db/local.db"]
        case .codebuddy: return ["\(home)/.codebuddy/projects"]
        case .windsurf: return ["\(home)/.codeium/windsurf/cascade"]
        case .antigravity: return ["\(home)/.gemini/antigravity/conversations", "\(home)/.gemini/antigravity-ide/conversations"]
        case .trae: return ["\(appSupport)/Trae/ModularData/ai-agent", "\(appSupport)/Trae CN/ModularData/ai-agent"]
        }
    }

    /// 界面上该显示的默认路径。演示模式换成 `/Users/you/...`：「数据源」页会把这几行
    /// 原样画出来，用真实默认值等于把作者的用户名写进提交进仓库的截图。
    var configuredDefaultPaths: [String] {
        guard DemoRuntime.isActive else { return defaultPaths }
        let home = NSHomeDirectory()
        return defaultPaths.map { $0.replacingOccurrences(of: home, with: "/Users/you") }
    }

    /// 本机是否检测到该工具（任一默认路径存在）
    var isDetected: Bool {
        // 演示模式给固定答案：真去 stat 磁盘的话，同一份代码在作者机器上和别人机器上
        // 截出来的「未检测到」徽标不一样，图就不可复现了（见 DemoRuntime）
        if DemoRuntime.isActive { return Self.demoDetected.contains(self) }
        return defaultPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// 演示模式里哪些工具算「检测到了」。TRAE 故意不在里面 ——
    /// 它是唯一一个「本地数据不可读」的数据源，截图里该有这么一枚徽标。
    static let demoDetected: Set<SourceKind> = [
        .claudeCode, .codex, .devin, .cursor, .qoder, .codebuddy, .windsurf, .antigravity,
    ]

    func makeProvider() -> UsageProvider {
        switch self {
        case .claudeCode: return ClaudeCodeProvider(kind: .claudeCode)
        case .codebuddy: return ClaudeCodeProvider(kind: .codebuddy)
        case .codex: return CodexProvider()
        case .devin: return DevinProvider()
        case .cursor: return CursorProvider()
        case .qoder: return QoderProvider()
        case .windsurf: return SessionFilesProvider(kind: .windsurf, fileExtension: "pb")
        case .antigravity: return SessionFilesProvider(kind: .antigravity, fileExtension: "pb")
        case .trae: return EmptyProvider()
        }
    }
}

struct SourceConfig: Codable, Equatable {
    var enabled: Bool = true
    var paths: [String]
}
