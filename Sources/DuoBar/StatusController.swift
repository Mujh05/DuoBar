import AppKit
import SwiftUI

/// 菜单栏图标和弹出面板。
@MainActor
final class StatusController: NSObject {
    private let model: AppModel
    private var statusItem: NSStatusItem
    private let panel: MenuPanelController
    private let settings: SettingsWindowController
    private var percentAnimationTask: Task<Void, Never>?
    private var embeddedPercentProgress: CGFloat = 0
    private var embeddedPercentTarget: CGFloat = 0
    private var percentStyleInitialized = false

    /// 系统按这个名字记住图标在菜单栏里的位置（用户按住 ⌘ 拖动后也会记住）。
    private static let autosaveName = "DuoBar"

    init(model: AppModel) {
        self.model = model
        settings = SettingsWindowController(model: model)
        statusItem = Self.makeStatusItem()
        panel = MenuPanelController(rootView: PanelView(model: model))
        super.init()

        panel.onShow = { [weak model] in model?.panelVisible = true }
        panel.onClose = { [weak model] in model?.panelVisible = false }
        model.onIconChange = { [weak self] in self?.updateButton() }
        model.onOpenSettings = { [weak self] in
            self?.panel.close()
            self?.settings.show()
        }
        model.onClosePanel = { [weak self] in
            self?.panel.close()
        }
        configureButton()
    }

    private static func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        return item
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        button.imagePosition = .imageOnly
        percentAnimationTask?.cancel()
        percentStyleInitialized = false
        updateButton()
    }

    /// 开发用：打印图标在屏幕上的位置。
    var statusItemFrame: NSRect {
        statusItem.button?.window?.frame ?? .zero
    }

    func updateButton() {
        let state = model.iconState
        let availablePercent = model.battery.hasBattery && state.ring != nil ? model.battery.percent : nil
        let target: CGFloat = model.percentMode == .onRing && availablePercent != nil ? 1 : 0

        if !percentStyleInitialized {
            percentStyleInitialized = true
            embeddedPercentProgress = target
            embeddedPercentTarget = target
        } else if target != embeddedPercentTarget {
            animateEmbeddedPercent(to: target)
        }

        renderButton(state: state, availablePercent: availablePercent)
    }

    private func renderButton(state: IconState? = nil, availablePercent: Int? = nil) {
        guard let button = statusItem.button else { return }
        let state = state ?? model.iconState
        let percent = availablePercent ?? (model.battery.hasBattery && state.ring != nil ? model.battery.percent : nil)
        button.image = MenuBarIcon.image(for: state, scale: CGFloat(model.iconScale),
                                         embeddedPercent: percent,
                                         embeddedPercentProgress: embeddedPercentProgress)

        // 从圆环样式切回左侧文字时，等圆环收拢后再显示文字，避免两个数字短暂重叠。
        let hidesTitle = embeddedPercentTarget > 0 || embeddedPercentProgress > 0.001
        let title = hidesTitle ? "" : model.percentTitle ?? ""
        if button.title != title {
            button.title = title
            button.imagePosition = title.isEmpty ? .imageOnly : .imageTrailing
        }
        button.toolTip = model.accessibilitySummary
        button.setAccessibilityLabel(model.accessibilitySummary)
    }

    /// 约 0.34 秒的临界阻尼过渡；重新切换时从当前画面继续，不会跳回起点。
    private func animateEmbeddedPercent(to target: CGFloat) {
        percentAnimationTask?.cancel()
        embeddedPercentTarget = target

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            embeddedPercentProgress = target
            renderButton()
            return
        }

        let start = embeddedPercentProgress
        let distance = abs(target - start)
        guard distance > 0.001 else {
            embeddedPercentProgress = target
            renderButton()
            return
        }

        let duration = max(0.14, 0.34 * Double(distance))
        percentAnimationTask = Task { @MainActor [weak self] in
            let began = ProcessInfo.processInfo.systemUptime
            while let self, !Task.isCancelled {
                let elapsed = ProcessInfo.processInfo.systemUptime - began
                let time = min(max(elapsed / duration, 0), 1)
                let eased = Self.criticallyDamped(CGFloat(time))
                self.embeddedPercentProgress = start + (target - start) * eased
                self.renderButton()
                if time >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard let self, !Task.isCancelled else { return }
            self.embeddedPercentProgress = target
            self.renderButton()
        }
    }

    private static func criticallyDamped(_ time: CGFloat) -> CGFloat {
        let response: CGFloat = 7
        let value = 1 - (1 + response * time) * exp(-response * time)
        let end = 1 - (1 + response) * exp(-response)
        return value / end
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if panel.isShown {
            panel.close()
        } else {
            panel.show(below: sender)
        }
    }

    /// 开发用：打开设置窗口的某一页停留几秒，打印窗口位置，方便用 screencapture 截下真实效果。
    func debugShowSettings(page: SettingsPage, seconds: Double) async {
        model.requestedSettingsPage = page
        settings.show(activate: false)
        let wait = ProcessInfo.processInfo.environment["DUOBAR_DEBUG_WAIT"].flatMap(Double.init) ?? 1.5
        try? await Task.sleep(for: .seconds(wait))
        if let window = settings.contentView?.window {
            let screenTop = (window.screen ?? NSScreen.main)?.frame.maxY ?? 0
            print(String(format: "settings frame (screencapture -R): %.0f,%.0f,%.0f,%.0f",
                         window.frame.minX, screenTop - window.frame.maxY, window.frame.width, window.frame.height))
            // 窗口可能被别的 App 挡住：用 screencapture -l 按编号只截这个窗口，不会截到别的内容。
            print("settings window (screencapture -l):", window.windowNumber)
            fflush(stdout)
        }
        try? await Task.sleep(for: .seconds(seconds))
        settings.close()
    }

    /// 开发用：打开面板（可以指定展开哪一项和深浅色）并停留几秒，打印它在屏幕上的位置，方便用 screencapture 截下真实的玻璃效果。
    func debugShowPanel(tab: PanelTab?, appearance: NSAppearance?, seconds: Double) async {
        guard let button = statusItem.button else { return }
        let split = ProcessInfo.processInfo.environment["DUOBAR_DEBUG_SPLIT"].flatMap(Double.init).map { CGFloat($0) }
        let preview = MenuPanelController(rootView: PanelView(model: model, previewTab: tab, previewSplit: split),
                                          appearance: appearance)
        preview.onShow = { [weak model] in model?.panelVisible = true }
        preview.onClose = { [weak model] in model?.panelVisible = false }
        if let ssid = ProcessInfo.processInfo.environment["DUOBAR_DEBUG_PASSWORD_PROMPT"] {
            model.debugShowPasswordPrompt(for: ssid, hint: ProcessInfo.processInfo.environment["DUOBAR_DEBUG_PASSWORD_HINT"])
        }
        preview.show(below: button)
        print("menu bar appearance:", button.effectiveAppearance.name.rawValue)
        // 等采样、扫描和面板的淡入完成；DUOBAR_DEBUG_WAIT 可以改等待的秒数。
        let wait = ProcessInfo.processInfo.environment["DUOBAR_DEBUG_WAIT"].flatMap(Double.init) ?? 1.5
        try? await Task.sleep(for: .seconds(wait))
        let frame = preview.frame
        let screenTop = (button.window?.screen ?? NSScreen.main)?.frame.maxY ?? 0
        print(String(format: "panel frame (screencapture -R): %.0f,%.0f,%.0f,%.0f",
                     frame.minX, screenTop - frame.maxY, frame.width, frame.height))
        fflush(stdout)
        try? await Task.sleep(for: .seconds(seconds))
        preview.close()
        try? await Task.sleep(for: .seconds(0.3))
    }

    /// 开发用：把菜单栏按钮和打开过程中的面板截成 PNG，不需要屏幕录制权限。
    func debugSnapshot(to directory: URL) async {
        guard let button = statusItem.button else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Self.snapshot(button, to: directory.appendingPathComponent("statusitem.png"))
        print("status item frame:", button.window?.frame ?? .zero, "appearance:", button.effectiveAppearance.name.rawValue)

        if ProcessInfo.processInfo.environment["DUOBAR_PRETEND_VERSION"] != nil {
            await model.checkForUpdates(manual: true)
        }
        panel.show(below: button)
        var elapsed = 0.0
        for moment in [0.15, 3.0] {
            try? await Task.sleep(for: .seconds(moment - elapsed))
            elapsed = moment
            Self.snapshot(panel.contentView, to: directory.appendingPathComponent(String(format: "panel-%.2fs.png", moment)))
        }
        print("panel frame:", panel.frame)
        panel.close()

        // 每个位置展开后的样子（面板打开时扫描到的网络还留着）。离屏渲染画不出玻璃，垫一层灰底。
        for slot in Slot.allCases where model.layout[slot] != nil {
            await snapshotOffscreen(PanelView(model: model, previewTab: .slot(slot)).background(Color(white: 0.9)),
                                    width: MenuMetrics.width, to: directory.appendingPathComponent("panel-tab-\(slot).png"))
        }

        // 设置窗口：等采样把所有状态都读一遍再截图。
        settings.show(activate: false)
        try? await Task.sleep(for: .seconds(2.5))
        if let view = settings.contentView {
            Self.snapshot(view, to: directory.appendingPathComponent("settings.png"))
        }

        // 每一页的完整内容：放在屏幕外足够高的窗口里渲染，不用滚动。“图标”页再渲染一张深色的。
        let pages = SettingsPage.allCases.map { ($0, false) } + [(SettingsPage.icon, true)]
        for (page, dark) in pages {
            let height: CGFloat = page == .icon || page == .indicators || page == .metrics ? 1300 : 800
            let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 780, height: height),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            if dark { window.appearance = NSAppearance(named: .darkAqua) }
            let host = NSHostingView(rootView: SettingsRoot(model: model, page: page))
            window.contentView = host
            window.orderFront(nil)
            try? await Task.sleep(for: .seconds(page == .icon ? 1.2 : 0.8))
            let name = "settings-\(page.rawValue)\(dark ? "-dark" : "").png"
            Self.snapshot(host, to: directory.appendingPathComponent(name))
            window.orderOut(nil)
        }
        settings.close()
    }

    /// 放在屏幕外的窗口里按理想高度渲染，AppKit 控件也能正常画出来。
    private func snapshotOffscreen(_ root: some View, width: CGFloat, to url: URL) async {
        let host = NSHostingView(rootView: root)
        let height = max(host.fittingSize.height, 100)
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        try? await Task.sleep(for: .seconds(0.6))
        Self.snapshot(host, to: url)
        window.orderOut(nil)
    }

    private static func snapshot(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        PreviewRenderer.write(rep, to: url)
    }

}
