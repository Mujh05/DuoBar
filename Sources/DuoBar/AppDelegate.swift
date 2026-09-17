import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 开发用的启动参数。
    enum DebugAction {
        /// 截下菜单栏按钮、面板和设置窗口后退出。
        case snapshot(URL)
        /// 打印图标在菜单栏里的位置后退出。
        case reportPosition
    }

    private let model = AppModel()
    private var statusController: StatusController?
    private let debugAction: DebugAction?

    init(debugAction: DebugAction? = nil) {
        self.debugAction = debugAction
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusController(model: model)
        statusController = controller
        model.start()

        guard let debugAction else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            switch debugAction {
            case let .snapshot(directory):
                await controller.debugSnapshot(to: directory)
            case .reportPosition:
                let frame = controller.statusItemFrame
                let screen = NSScreen.main?.frame.width ?? 0
                print("status item x=\(frame.minX) width=\(frame.width) distance from right edge=\(screen - frame.maxX)")
            }
            NSApp.terminate(nil)
        }
    }
}
