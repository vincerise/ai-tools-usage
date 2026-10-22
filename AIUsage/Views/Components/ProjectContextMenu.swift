import SwiftUI

extension View {
    /// 项目维度的右键入口。看板卡与明细行共用这一条，提示文案才不会两处各说各的。
    ///
    /// `enabled` 让非项目维度不必挂一个空菜单；路径为空（未归类）时仍然挂上 ——
    /// 点下去会说明为什么没有位置，而不是把菜单项藏起来让人猜。
    @ViewBuilder
    func projectContextMenu(path: String, enabled: Bool = true,
                            onMerge: (() -> Void)? = nil) -> some View {
        if enabled {
            contextMenu {
                Button("在访达中打开项目") { ProjectOpener.openWithFeedback(path: path) }
                if let onMerge {
                    Divider()
                    Button("合并到另一个项目…", action: onMerge)
                }
            }
        } else {
            self
        }
    }
}
