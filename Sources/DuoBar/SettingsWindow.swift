import AppKit
import SwiftUI

/// 设置窗口左侧的分页。
enum SettingsPage: String, CaseIterable, Identifiable, Sendable {
    case icon, metrics, indicators, menuBar, updates, general

    var id: Self { self }

    var title: String {
        switch self {
        case .icon: "图标"
        case .metrics: "状态"
        case .indicators: "指示灯"
        case .menuBar: "菜单栏"
        case .updates: "更新"
        case .general: "通用"
        }
    }

    /// 侧边栏图标的底色；图形见 PageGlyph。
    var color: Color {
        switch self {
        case .icon: .blue
        case .metrics: .green
        case .indicators: .orange
        case .menuBar: .purple
        case .updates: .pink
        case .general: .gray
        }
    }
}

/// 设置窗口，和系统设置一样：左侧分页，右侧是分组表单，窗口标题显示当前页的名字。
struct SettingsRoot: View {
    @Bindable var model: AppModel
    @State private var selection: SettingsPage?

    init(model: AppModel, page: SettingsPage = .icon) {
        self.model = model
        _selection = State(initialValue: page)
    }

    private var page: SettingsPage { selection ?? .icon }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selection) { page in
                Label {
                    Text(page.title)
                } icon: {
                    PageIcon(page: page)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            Form {
                content
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            // 换页时从顶部开始，不沿用上一页的滚动位置。
            .id(page)
        }
        .toolbar(removing: .sidebarToggle)
        .navigationTitle(page.title)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .icon: IconSettingsPage(model: model)
        case .metrics: MetricsSettingsPage(model: model)
        case .indicators: IndicatorsSettingsPage(model: model)
        case .menuBar: MenuBarSettingsPage(model: model)
        case .updates: UpdatesSettingsPage(model: model)
        case .general: GeneralSettingsPage(model: model)
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    static let defaultSize = NSSize(width: 780, height: 620)

    init(model: AppModel) {
        self.model = model
    }

    var contentView: NSView? { window?.contentView }

    func show(activate: Bool = true) {
        let window = self.window ?? makeWindow()
        self.window = window
        model.settingsVisible = true
        if activate { NSApp.activate() }
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsRoot(model: model))
        // 让 SwiftUI 的工具栏设置（去掉侧栏按钮）和标题同步到窗口上。
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.contentViewController = controller
        window.setContentSize(Self.defaultSize)
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 680, height: 460)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("DuoBarSettingsWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.settingsVisible = false
    }
}
