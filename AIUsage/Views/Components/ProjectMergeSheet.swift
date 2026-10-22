import SwiftUI

/// 手动合并项目：把旧路径下的历史并到新项目名下。
///
/// 目录改名之后，账不会自己跟过去 —— 旧绝对路径仍是一个独立项目。这里只建立一条路径映射，
/// 不动文件、不改日志；合并结果随时可以在设置里撤销。
struct ProjectMergeSheet: View {
    @EnvironmentObject var store: UsageStore
    @Environment(\.dismiss) private var dismiss

    /// 从看板 / 明细右键打开时带进来的「旧项目」；从设置里打开时为空。
    let initialSource: String?

    @State private var sourceID: String?
    @State private var targetID: String?

    init(initialSource: String? = nil) {
        self.initialSource = initialSource
        _sourceID = State(initialValue: initialSource)
    }

    private var keys: [String] {
        var keys = store.knownProjectKeys
        // 来源可能因为别名刚改过而不在列表里（例如手改过配置）；仍要能看见它
        if let source = initialSource, !source.isEmpty, !keys.contains(source) {
            keys.append(source)
            keys.sort()
        }
        return keys
    }

    private var labels: [String: String] { ProjectResolver.labels(for: keys) }

    private func label(_ key: String) -> String { labels[key] ?? key }

    private var targets: [String] { keys.filter { $0 != sourceID } }

    private var canMerge: Bool {
        guard let source = sourceID, let target = targetID else { return false }
        return !source.isEmpty && !target.isEmpty && source != target
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("合并项目")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.gray900)
                Text("目录改名或搬家后，旧路径和新路径会分成两个项目。合并后旧项目按目标项目的名字显示，用量、费用与请求数都算在一起。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.gray600)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                pickerRow("原项目", selection: $sourceID, options: keys)
                pickerRow("合并到", selection: $targetID, options: targets)
            }

            if let source = sourceID, let target = targetID, source != target {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ProjectResolver.displayPath(source))
                    Text("→ \(ProjectResolver.displayPath(target))")
                }
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.gray500)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.tableHeader, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            Text("只影响本机的分组与导出：不移动、不删除任何文件，也不改动扫描到的日志。可在 设置 → 显示与留存 → 项目合并 里撤销。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.gray500)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("合并") { merge() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canMerge)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.pageBackground)
        .onChange(of: sourceID) { _, newValue in
            if targetID == newValue { targetID = nil }
        }
    }

    private func pickerRow(_ title: String, selection: Binding<String?>, options: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.gray700)
                .frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Picker(title, selection: selection) {
                    Text("选择项目").tag(String?.none)
                    ForEach(options, id: \.self) { key in
                        Text(label(key)).tag(Optional(key))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                if let key = selection.wrappedValue {
                    Text(ProjectResolver.displayPath(key))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.gray500)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func merge() {
        guard let source = sourceID, let target = targetID, canMerge else { return }
        store.addProjectAlias(from: source, to: target)
        dismiss()
    }
}
