import SwiftUI

/// 「项目看板」：图表与明细表之间的一排项目卡。
///
/// 只回答一个问题：**这个范围里哪些项目最烧钱**。所以：
/// - 只列**归得到项目**的行；「未归类」单独放页脚。把未归类混进排名里，
///   第一名可能是一个根本不知道是谁的项目，这张卡就白摆了。
/// - 费用口径下未计价模型的金额是下界，数字前写 `≥`（与明细表、KPI 卡同一个写法）。
/// - 点一块卡 = 让下方明细表切到「按项目」并按同一口径降序 —— 看板与明细在同一视线里。
///
/// **布局用 `GeometryReader` 算宽，不用 `LazyVGrid`**：离屏渲染工装（`--render`）用的是
/// `ImageRenderer`，懒加载容器里的内容不会进快照 —— 那张图上会只剩一个空卡片。
struct ProjectBoardView: View {
    @EnvironmentObject var store: UsageStore

    @State private var metric: Metric = .cost
    /// 右键「合并到另一个项目…」选中的来源。sheet 挂在卡片这一层，
    /// 不挂在每块 tile 上 —— 与模型详情同一个理由：行/卡会被懒加载回收，锚点会飘。
    @State private var mergeSource: BreakdownRow?

    private static let maxTiles = 6
    private static let tileSpacing: CGFloat = 12
    private static let tileHeight: CGFloat = 136

    /// 有项目路径的行。空 id 是「未归类」，不参与排名。
    private var assigned: [BreakdownRow] {
        store.snapshot.byProject.filter { !$0.id.isEmpty }
    }

    private var unassigned: BreakdownRow? {
        store.snapshot.byProject.first { $0.id.isEmpty }
    }

    /// 按当前口径排名。费用同值时用 tokens 兜底 —— 与 `recompute` 里那个稳定排序一致，
    /// 截图和数据层不会因为 `sorted` 不稳定而各排各的。
    private var ranked: [BreakdownRow] {
        assigned.sorted { a, b in
            let x = metric == .cost ? (a.cost ?? -1) : Double(a.tokens)
            let y = metric == .cost ? (b.cost ?? -1) : Double(b.tokens)
            if x == y { return a.label.localizedStandardCompare(b.label) == .orderedAscending }
            return x > y
        }
    }

    private var shown: [BreakdownRow] { Array(ranked.prefix(Self.maxTiles)) }

    private var subtitle: String {
        var s = "\(store.projectGrouping.label) · 共 \(assigned.count) 个项目"
        if assigned.count > Self.maxTiles { s += " · 前 \(Self.maxTiles) 个" }
        return s
    }

    /// 占比口径跟着看板的指标走，与明细表「占比按排序口径」那条规矩是同一条。
    /// 分母为 0 时返回 nil（画「—」），而不是 0.0% —— 那会被读成「真的只占这么点」。
    private func share(_ row: BreakdownRow) -> Double? {
        switch metric {
        case .cost:
            guard store.snapshot.totals.cost > 0 else { return nil }
            return store.snapshot.share(of: row, by: .cost)
        case .tokens:
            guard store.snapshot.totals.processed > 0 else { return nil }
            return store.snapshot.share(of: row, by: .tokens)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader("项目看板", subtitle: subtitle) {
                SegmentedControl(options: [(Metric.cost, "费用"), (Metric.tokens, "Tokens")],
                                 selection: $metric, itemWidth: 54, height: 26)
            }
            if shown.isEmpty {
                Text("所选范围内没有可归类的项目")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.gray500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                GeometryReader { geo in
                    let n = CGFloat(shown.count)
                    // 卡片不铺满整行：超过 260pt 一块会显得空，窄窗口下按可用宽度等分
                    let width = min(260, max(120, (geo.size.width - (n - 1) * Self.tileSpacing) / n))
                    HStack(spacing: Self.tileSpacing) {
                        ForEach(shown) { row in
                            tile(row).frame(width: width)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: Self.tileHeight)
                unassignedFooter
            }
        }
        .card()
        .sheet(item: $mergeSource) { row in
            ProjectMergeSheet(initialSource: row.id)
                .environmentObject(store)
        }
    }

    private func tile(_ row: BreakdownRow) -> some View {
        Tile(row: row, metric: metric, share: share(row),
             action: {
                 store.sort.key = metric == .cost ? .cost : .tokens
                 store.sort.ascending = false
                 store.breakdown = .project
             },
             onMerge: { mergeSource = row })
    }

    /// 「未归类」不是页脚装饰：它说明有多少 token 实在归不到项目上。
    /// 这些 token **已经计入 KPI 与折线图**，只是没有路径 —— 不能让它从看板上凭空消失。
    @ViewBuilder
    private var unassignedFooter: some View {
        if let u = unassigned, u.tokens > 0 {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle").font(.system(size: 11))
                Text("未归类 \(Formatters.tokens(u.tokens)) tokens")
                if let c = u.cost {
                    Text("· \(u.unpriced ? "≥" : "")\(Formatters.cost(c))")
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.gray500)
            .monospacedDigit()
            .help("这些数据源没有提供工作目录：Qoder、加密数据源，或旧版本 App 写的设备档案。它们的 token 仍然计入上方总计，只是归不到具体项目。\n右键可查看说明")
            .projectContextMenu(path: "")
        }
    }

    // MARK: 单块

    private struct Tile: View {
        let row: BreakdownRow
        let metric: Metric
        let share: Double?
        let action: () -> Void
        /// 右键菜单里的「合并到另一个项目…」；由看板这一层弹出 sheet
        let onMerge: () -> Void

        @State private var hovering = false

        private var primary: String {
            metric == .cost ? Formatters.cost(row.cost ?? 0) : Formatters.tokens(row.tokens)
        }

        private var secondary: String {
            let requests: String
            if row.requests > 0 {
                requests = (row.requestsPartial ? "≥" : "") + Formatters.count(row.requests) + " 次"
            } else {
                requests = "—"
            }
            switch metric {
            case .cost: return "\(Formatters.tokens(row.tokens)) tokens · \(requests)"
            case .tokens: return "\(row.cost.map(Formatters.cost) ?? "未计价") · \(requests)"
            }
        }

        private var orderedProviders: [ProviderKind] {
            row.providers.sorted {
                let a = row.providerTokens[$0] ?? 0
                let b = row.providerTokens[$1] ?? 0
                return a == b ? $0.rawValue < $1.rawValue : a > b
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.gray900)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ProjectResolver.displayPath(row.id))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.gray500)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if metric == .cost, row.unpriced {
                        Text("≥").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gray500)
                    }
                    Text(primary)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.gray900)
                        .monospacedDigit()
                        .lineLimit(1)
                        // 窄窗口（1180pt）下六块并排时每块只有 ~170pt，长金额要能缩一点
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
                Text(secondary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.gray500)
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer(minLength: 0)
                shareBar
                providerDots
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.tableHeader, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(hovering ? Theme.primary.opacity(0.45) : Theme.cardBorder))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .projectContextMenu(path: row.id, onMerge: onMerge)
            .help("\(ProjectResolver.displayPath(row.id))\n点击在下方明细里按这个项目查看；右键可在访达中打开或合并项目")
        }

        private var shareBar: some View {
            HStack(spacing: 6) {
                GeometryReader { geo in
                    Capsule().fill(Theme.divider)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.primary)
                                .frame(width: (share ?? 0) > 0
                                       ? max(4, geo.size.width * CGFloat(min(1, share ?? 0)))
                                       : 0)
                        }
                }
                .frame(height: 5)
                Text(share.map(Formatters.percent) ?? "—")
                    .font(.system(size: 10.5))
                    .foregroundStyle(share == nil ? Theme.gray500 : Theme.gray700)
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
            .frame(height: 10)
        }

        /// 最多 4 个环境圆点，其余收进 `+N`；tooltip 里列全名称与 token，
        /// 颜色只是辅助身份，读不出名字时 tooltip 是那条不靠颜色的路径。
        private var providerDots: some View {
            let ordered = orderedProviders
            let visible = Array(ordered.prefix(4))
            let hidden = Array(ordered.dropFirst(4))
            return HStack(spacing: 4) {
                ForEach(visible) { p in
                    Circle().fill(p.accent).frame(width: 6, height: 6)
                }
                if !hidden.isEmpty {
                    Text("+\(hidden.count)")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.gray500)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 8)
            .help(ordered.map { "\($0.displayName) \(Formatters.tokens(row.providerTokens[$0] ?? 0))" }
                    .joined(separator: "\n"))
        }
    }
}
