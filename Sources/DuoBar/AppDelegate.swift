import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 开发用的启动参数。
    enum DebugAction {
        /// 截下菜单栏按钮、面板和设置窗口后退出。
        case snapshot(URL)
        /// 打印图标在菜单栏里的位置后退出。
        case reportPosition
        /// 只读地检查 Wi-Fi 扫描后退出。
        case wifiReport
        /// 查询 GitHub 上的最新版本，把安装包下载到指定目录并校验后退出。
        case updateReport(URL)
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
            case .wifiReport:
                print("location: \(model.ssidAccess)")
                print(await WiFiControl.debugSummary())
            case let .updateReport(directory):
                await Self.reportUpdate(downloadingTo: directory)
            }
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    private static func reportUpdate(downloadingTo directory: URL) async {
        let comparisons = [("1.10", "1.9"), ("1.1", "1.1.0"), ("1.0.1", "1.0"), ("1.0", "1.1")]
        for (a, b) in comparisons {
            print("isNewer(\(a), \(b)) = \(UpdateChecker.isNewer(a, than: b))")
        }
        do {
            let release = try await UpdateChecker.latestRelease()
            print("current: \(UpdateChecker.currentVersion)")
            print("latest: \(release.version) page: \(release.pageURL)")
            print("dmg: \(release.dmgName ?? "none") sha256: \(release.sha256 ?? "none")")
            print("newer than current: \(UpdateChecker.isNewer(release.version, than: UpdateChecker.currentVersion))")
            let file = try await UpdateChecker.download(release, to: directory)
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            print("downloaded and verified: \(file.lastPathComponent) (\(size) bytes)")
        } catch {
            print("update check failed: \(error.localizedDescription)")
        }
    }
}
