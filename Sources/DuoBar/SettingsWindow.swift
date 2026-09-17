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

    var subtitle: String {
        switch self {
        case .icon: "三个位置显示什么、图标多大、要不要变色"
        case .metrics: "可以放在图标上的 9 种状态和它们的实时数值"
        case .indicators: "底部 4 个圆点各自显示的开关状态"
        case .menuBar: "电量百分比、图标位置和系统自带的图标"
        case .updates: "检查 GitHub 上有没有新版本"
        case .general: "面板、启动和关于 DuoBar"
        }
    }

    var symbol: String {
        switch self {
        case .icon: "paintbrush.pointed.fill"
        case .metrics: "gauge.with.dots.needle.67percent"
        case .indicators: "circle.grid.2x2.fill"
        case .menuBar: "menubar.rectangle"
        case .updates: "arrow.down.circle.fill"
        case .general: "gearshape.fill"
        }
    }

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

/// 设置窗口：左侧分页，右侧内容，切换时淡入并轻轻上移。
struct SettingsRoot: View {
    @Bindable var model: AppModel
    @State private var selection: SettingsPage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    IconBadge(symbol: page.symbol, color: page.color, size: 20)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    content
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 660, alignment: .leading)
                .frame(maxWidth: .infinity)
                .id(page)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 14)))
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.35), value: page)
        }
        .toolbar(removing: .sidebarToggle)
        .navigationTitle("DuoBar 设置")
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: page.symbol, color: page.color, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .font(.system(size: 21, weight: .bold))
                Text(page.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 2)
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
