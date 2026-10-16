import Foundation
import ServiceManagement

/// 「登录时自动启动」。
///
/// **走系统自己的登录项（`SMAppService.mainApp`），不自己装 LaunchAgent**：后者要在
/// `~/Library/LaunchAgents` 里落一个 plist，卸载时还得自己记得删干净；`SMAppService` 由系统管，
/// 关掉就是注销掉，系统设置 → 通用 → 登录项里也看得见 —— 用户想自己关随时关得掉。
///
/// 键名那套约定在这里用不上：**这一项不落自己的盘**。真相在系统那一侧（用户可以直接在
/// 系统设置里关掉它），自己再存一个 bool 就有了两个真相来源，迟早对不上。
enum LaunchAtLogin {
    /// 界面上要分出来的三种情况。跟 `SMAppService.Status` 不是一一对应（那边 `.notFound`
    /// 与 `.notRegistered` 都归到这里的 `off`，理由见 `state(of:)`），也不直接用它：
    /// 系统那个枚举带着 SDK 版本、`@unknown default` 之类的包袱，界面不该跟着它走。
    enum State: Equatable {
        /// 已登记，登录时会起
        case on
        /// 没登记
        case off
        /// 登记上了，但系统在等用户批准（系统设置 → 通用 → 登录项）
        case needsApproval
    }

    /// 纯映射。抽成函数是为了自测 —— 这一层没有任何副作用，量它安全。
    ///
    /// **`.notFound` 在这里按「没开」处理，不按「用不了」** —— 这一条是量出来的，不是推的：
    /// 实测（ad-hoc 签名、App 放在 `/Applications`、从没登记过）**没登记时系统给的就是
    /// `.notFound`**，而这时候 `register()` 一把就成功、之后状态变成 `.enabled`。
    /// 也就是说 `.notFound` 表示的是「系统那边没有这个 App 的登录项记录」，不是「系统不认这个 App」。
    /// 要是按「用不了」处理，**所有还没登记过的人看到的都是一个灰掉的开关**，这功能等于没有。
    /// （注销之后状态会变成 `.notRegistered` —— 同一个「没开」，走了两条不同的路回来。）
    static func state(of status: SMAppService.Status) -> State {
        switch status {
        case .enabled: return .on
        case .notRegistered, .notFound: return .off
        case .requiresApproval: return .needsApproval
        // 将来多出来的状态也按「没开」处理：让用户点得动，真不行的话 register() 会说话
        @unknown default: return .off
        }
    }

    /// 真正动系统的那一层。**抽成协议只有一个理由：自测**。
    /// `SelfTest` 里绝不许真的注册登录项（那是在用户的机器上留东西，跑一次自测留一个，
    /// 而且是在别人的系统设置里），所以那一组拿的是假实现，见 `SelfTest.testLaunchAtLogin`。
    @MainActor
    protocol Service: AnyObject {
        var state: State { get }
        func register() throws
        func unregister() throws
    }

    /// 真的去动系统。**只该在用户拨那个开关的时候被调到**。
    @MainActor
    final class SystemService: Service {
        var state: State { LaunchAtLogin.state(of: SMAppService.mainApp.status) }
        func register() throws { try SMAppService.mainApp.register() }
        func unregister() throws { try SMAppService.mainApp.unregister() }
    }

    /// 演示模式（`--demo` / 出图）用的：**只动内存，一个系统调用都不发**。
    ///
    /// 出图不该在作者机器上留下一个真登录项（那是在别人的系统设置里留东西），
    /// 而演示二进制是从 build 目录跑的、登记也未必成 —— 所以这里报一个普通的「没开」，
    /// 点一下只改内存，README 那张图里就是一个正常可点的开关。
    @MainActor
    final class DemoService: Service {
        private var inMemory: State = .off
        var state: State { inMemory }
        func register() { inMemory = .on }
        func unregister() { inMemory = .off }
    }
}

/// 开关的状态机。**自己不存 bool**：系统的状态就是唯一真相，所以每次动完都回头问一遍系统，
/// 而不是照着「我刚才发过 register」猜 —— 系统可能没接受，也可能把这一项标成「等批准」。
@MainActor
final class LaunchAtLoginSettings: ObservableObject {
    @Published private(set) var state: LaunchAtLogin.State
    /// 上一次动作失败的原因（下一次成功时清回 nil）
    @Published private(set) var errorMessage: String?

    private let service: LaunchAtLogin.Service

    /// `service` 收可选而不是写 `= LaunchAtLogin.SystemService()`：默认参数在**非隔离**上下文里
    /// 求值，而 `SystemService` 是 `@MainActor` 的 —— 写成默认值编译不过
    /// （`UpdateService.init` 为同一件事记过一次账）。
    init(service: LaunchAtLogin.Service? = nil) {
        let resolved = service
            ?? (DemoRuntime.isActive ? LaunchAtLogin.DemoService() : LaunchAtLogin.SystemService())
        self.service = resolved
        state = resolved.state
    }

    /// 界面上那个开关的位置。**`.needsApproval` 算「开」**：系统那边确实登记上了，只是还差用户点头。
    /// 这时候把开关画成关着的，用户会以为刚才那下没生效、然后再点一次 —— 而那一次是注销。
    /// 开关跟着「登记没登记」走，「还差批准」另外用一行字说。
    var isOn: Bool { state == .on || state == .needsApproval }

    /// 拨开关。失败时状态不动、只留一句话：这一项成不成由系统说了算，界面不替它表态。
    func setEnabled(_ on: Bool) {
        errorMessage = nil
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            errorMessage = Self.describe(error)
        }
        refresh()
    }

    /// 重新问一遍系统。**App 回到前台时要调**：用户很可能刚去了系统设置里改这一项。
    func refresh() { state = service.state }

    /// 失败时给用户看的那句话。纯函数，好测。
    ///
    /// 后面那半句是有用的：这条路上真出过的错几乎都同一类 —— App 不在系统认可的位置
    /// （下载目录、build 目录、被 Gatekeeper 挪进随机路径），或者签名让系统不认。
    /// 光把系统的原话摆出来（「The operation couldn't be completed. (SMErrorDomain error 1.)」）
    /// 等于什么都没说。
    static func describe(_ error: Error) -> String {
        "系统没有接受这次改动：\(error.localizedDescription) —— 若一直失败，把 App 拖进「应用程序」再试。"
    }
}
