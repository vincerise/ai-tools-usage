import SwiftUI
import AppKit

/// 「定时刷新」下拉。**两处共用**：主窗口筛选行的工具组、菜单栏面板的标题行。
///
/// 状态只有一份（`store.refreshMinutes`），所以两处永远显示同一个档位 ——
/// 在面板里改成 10 分钟，主窗口那颗按钮上的字跟着变，反之亦然。
///
/// **按钮自绘 + `NSMenu`，不用 SwiftUI 的 `Menu`**：与 `ExportMenu` 同一条账 ——
/// `Menu` 由 AppKit 承载，离屏出图会画成一个黄底红圈的禁止符号，而这两处**都在
/// `--render` 的出图范围里**（主界面与面板各有一张快照），出图一旦出方块就没法当回归基线了。
struct RefreshIntervalControl: View {
    @ObservedObject var store: UsageStore
    /// 菜单栏面板那一档：更矮、无边框（面板标题行只有 30pt 高，且底色就是面板底色）
    var compact = false

    /// 「自定义…」选完之后按钮**原地**变成输入框，不弹窗：面板是 `MenuBarExtra` 那种
    /// 一点外面就收起来的窗口，模态框在里面既别扭又要抢激活。
    @State private var editing = false
    @State private var draft = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: compact ? 6 : 9, style: .continuous)
    }

    var body: some View {
        if editing { field } else { button }
    }

    // MARK: 宽度

    /// 档位文字那一格的定宽。**定宽是有意的**，与日期胶囊里那格「· N 天」同一条账：
    /// 宽度不定的话，把档位从「30 分钟」改成「1440 分钟」，整条工具组会跟着往右长，
    /// 而这一行离最小窗口宽度只剩十几 pt（见 `FilterBar.viewOptions`），长出来就得让
    /// 日期去换行。两个数都是**量出来的**（12pt / 11pt 等宽数字，AppKit `size(withAttributes:)`）：
    /// 最宽的一档是四位数的「1440 分钟」= 57.4 / 52.9，往上一档取整。
    /// 改字号、改文案、或者把上限从 1440 调大，都得重量一遍 —— `SelfTest` 里有一条
    /// 拿全部 0…1440 档去撞这两个常量的断言，量错了会在自测里红。
    static let labelWidth: CGFloat = 58
    static let compactLabelWidth: CGFloat = 54

    /// 整条控件的宽度：**收起态与编辑态共用同一个数**。
    ///
    /// 编辑态原本是按内容自己撑的，比收起态宽十来 pt，结果在最小窗口宽度下把日期挤去换行
    /// （`--render` 的 narrow 那几张量到过：日期断成「2026-07-1 / 4」）。两态同宽之后，
    /// 只要收起态放得下，编辑态就放得下 —— 这件事不再需要出图去盯。
    /// 编辑态里那把输入框是**可伸缩**的，多出来的那点宽度由它吃掉。
    ///
    /// 顺带记一笔：编辑态**出图看不出来**，离屏渲染画不出 `TextField`（和 `Menu` / `Form` 一样
    /// 是黄底红圈的占位块，实测），所以「两态同宽」只能靠这里的构造保证，没有快照可核。
    static func chipWidth(compact: Bool) -> CGFloat {
        (compact ? 6 : 10) * 2 + (compact ? compactLabelWidth : labelWidth) + 4 + (compact ? 8 : 10)
    }

    /// 这一格文字真正要占多宽（自测拿它核上面那两个常量够不够）。
    /// 把 0…1440 全量一遍而不是只量最长的那个：谁也没规定「最长的」一定是四位数。
    static func measuredLabelWidth(compact: Bool) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: compact ? 11 : 12, weight: .regular)
        return (RefreshInterval.off...RefreshInterval.validRange.upperBound)
            .map { (RefreshInterval.label($0) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
    }

    // MARK: 按钮

    private var button: some View {
        Button { popUp() } label: {
            // 不带图标：这一行是**贴着最小窗口宽度**过的账（见 `FilterBar.viewOptions`），
            // 一个 12pt 的 timer 加它那 6pt 间距要 24pt，而字面自己已经把话说全了 ——
            // 省下这 24pt，日期胶囊才不至于被挤到换行（`main-*-narrow` 那几张出图盯着这件事）。
            // 字面比图标也更好认：档位是要读出来的，不是认出来的。
            HStack(spacing: 4) {
                Text(RefreshInterval.label(store.refreshMinutes))
                    .font(.system(size: compact ? 11 : 12))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: compact ? Self.compactLabelWidth : Self.labelWidth, alignment: .trailing)
                Image(systemName: "chevron.down")
                    .font(.system(size: compact ? 7.5 : 9, weight: .semibold))
                    .foregroundStyle(Theme.gray500)
                    // 箭头这一格也定宽：宽度账要能一眼算平（见 `chipWidth`），
                    // 而 SF Symbol 的字形宽度是随字号变的、不是整数
                    .frame(width: compact ? 8 : 10, alignment: .trailing)
            }
            .foregroundStyle(Theme.gray600)
            .padding(.horizontal, compact ? 6 : 10)
            .frame(height: compact ? 20 : 34)
            // 面板里不铺底也不描边：它的底色就是面板底色，再套一层卡片边会把标题行切碎
            .background(hovering ? Theme.hover : (compact ? Color.clear : Theme.cardBackground), in: shape)
            .overlay { if !compact { shape.stroke(Theme.cardBorder) } }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help("定时刷新：\(RefreshInterval.label(store.refreshMinutes))。点开可改档位，或填一个自定义的分钟数")
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    // MARK: 自定义分钟

    /// 输入框。**四个出口，两个点得到、两个按得到**：回车 / ✓ 提交，Esc / ✕ 放弃。
    ///
    /// 这里原先只有「回车提交」和「失焦也提交」两个出口，而这两个都**要输入框真的拿到过焦点**：
    /// 焦点一旦没落上，打字没反应、Esc 没反应，也就永远不会失焦 —— 而按钮这时候已经被输入框
    /// 换掉了，整条控件于是**一个出口都没有**（用户报的「点了自定义就卡住」就是这个状态）。
    /// 焦点为什么会落空没查到确凿的那一步（真窗口里实测是会落上的），但这不重要：
    /// 出口不该建立在「焦点一定拿得到」上面。现在那两个按钮**不依赖焦点**，点得到就行，
    /// 焦点那件事仍然尽力做（见 `onAppear`），它坏掉最多是打不了字，不会再把人关在里面。
    ///
    /// **不再拿失焦当提交**：撤下输入框会让焦点旁落，而那一次 blur 与「点 ✕」谁先到是没法保证的
    /// —— 按鼠标先失焦再触发按钮，于是就变成点「放弃」反而把值提交了。既然提交与放弃都是
    /// 明确的动作，就让它们只由明确的动作触发，别再从焦点状态里猜。代价是点到别处不会自动收起，
    /// 得自己按 ✓ 或 ✕ —— 这个代价是看得见的（两个按钮就在旁边），比「悄悄提交了」好。
    private var field: some View {
        HStack(spacing: 3) {
            // 宽度交给外面那层 `.frame(width: chipWidth)` 分配：它是这一行里唯一可伸缩的东西，
            // 数字多了（1440）就在框里滚，不会把整条控件撑宽
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: compact ? 11 : 12))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity)
                .focused($focused)
                .onSubmit { commit() }
                .onExitCommand { cancel() }
                // 只留数字、最多四位（上限 1440）。用 onChange 过滤而不是校验后报错：
                // 这个框里除了分钟数没有别的合法输入，让非法字符根本打不进去最省事。
                .onChange(of: draft) { _, now in
                    let digits = String(now.filter(\.isNumber).prefix(4))
                    if digits != now { draft = digits }
                }
                .onAppear {
                    // 抢焦点。第一拍常常落空（视图刚插进树，AppKit 那边的 field editor 还没建好），
                    // 所以再补一拍 —— 两次都置 true 是幂等的，谁先成谁算。
                    DispatchQueue.main.async { focused = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { if editing { focused = true } }
                }
            Text("分钟").font(.system(size: compact ? 8 : 9)).foregroundStyle(Theme.gray500)
            ExitButton(symbol: "checkmark", help: "用这个分钟数", tint: Theme.primary,
                       compact: compact, action: commit)
            ExitButton(symbol: "xmark", help: "放弃，保持原来的档位", tint: Theme.gray600,
                       compact: compact, action: cancel)
        }
        .padding(.horizontal, compact ? 5 : 6)
        // 与收起态同宽，见 `chipWidth`
        .frame(width: Self.chipWidth(compact: compact), height: compact ? 20 : 34)
        .background(Theme.fieldBackground, in: shape)
        .overlay { shape.stroke(Theme.fieldBorder) }
    }

    // MARK: 动作

    private func popUp() {
        let menu = NSMenu()
        let target = MenuActionTarget()
        let current = store.refreshMinutes
        // 第一行是标题：档位文字里不带「每」（省宽度，见 `RefreshInterval.label`），
        // 「30 分钟」单看是时长还是间隔就靠这一行说清楚。它是说明不是命令，所以禁用。
        let header = NSMenuItem(title: "定时刷新", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        // 「关闭」在列表开头：它和四个预设是同一层选择，不是藏在末尾的开关
        for minutes in [RefreshInterval.off] + RefreshInterval.presets {
            menu.addItem(target.add(RefreshInterval.label(minutes),
                                    checked: minutes == current) { store.setRefreshInterval(minutes) })
        }
        menu.addItem(.separator())
        let isCustom = RefreshInterval.isCustom(current)
        menu.addItem(target.add(isCustom ? "自定义…（\(current) 分钟）" : "自定义…",
                                checked: isCustom) { beginCustomEdit() })
        // `in: nil` 表示用屏幕坐标，而当前鼠标位置就是用户刚点的那个按钮
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        withExtendedLifetime(target) {}
    }

    private func beginCustomEdit() {
        draft = String(store.customRefreshMinutes)
        editing = true
    }

    private func commit() {
        guard editing else { return }
        editing = false
        // 空着、或者填了 0 就当作没改（`setRefreshInterval` 那边也会规整一次）：
        // 手里没数的时候，保持原样比猜一个值好
        guard let minutes = Int(draft), minutes > 0 else { return }
        store.setRefreshInterval(minutes, custom: minutes)
    }

    private func cancel() {
        editing = false
    }
}

/// 编辑态里的两个出口（提交 / 放弃）。**存在的全部意义是「一定点得到」**，
/// 所以它是个普通的 `Button`：不依赖焦点、不依赖失焦，鼠标点下去就成立 ——
/// 而它俩要解决的那个毛病，恰恰是「焦点没了，整条控件就一个出口都没有」。
///
/// 14pt 见方是这一格能给的极限（整条控件只有三十来 pt 宽），所以 hover 时补一层底色，
/// 不然这么小的图标看不出是可以点的东西。
private struct ExitButton: View {
    let symbol: String
    let help: String
    let tint: Color
    let compact: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: compact ? 12 : 14, height: compact ? 12 : 14)
                .background(hovering ? Theme.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
