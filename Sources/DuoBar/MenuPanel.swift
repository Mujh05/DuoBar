import AppKit
import os
import SwiftUI

/// 像系统菜单栏菜单（Wi-Fi、电池）一样的面板：没有箭头，贴着菜单栏出现在图标下面，
/// macOS 26 起用系统同款的玻璃材质。显示时不激活 DuoBar，前台 App 保持不变。
/// 点面板以外的地方、按 Esc、切到别的 App 时自动收起。
@MainActor
final class MenuPanelController: NSObject, NSWindowDelegate {
    var onShow: (() -> Void)?
    /// 开始收起：面板内容在这段时间里播放收起的动画。
    var onWillClose: (() -> Void)?
    var onClose: (() -> Void)?

    /// 收起动画的时长，和 PanelView 里合拢胶囊的动画一致。
    static let closeDuration: TimeInterval = 0.3

    private let panel = MenuPanel(contentRect: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: 100),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let host: SizingHostingView<AnyView>
    /// 开发时固定的深浅色；nil 时跟着菜单栏走。
    private let fixedAppearance: NSAppearance?
    private weak var anchor: NSStatusBarButton?
    private var closing = false
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?

    static let cornerRadius: CGFloat = 18

    var isShown: Bool { panel.isVisible && !closing }
    /// 最近一次开始收起面板的时间（开机以来的秒数，和 NSEvent.timestamp 同一个时间基准）。
    private var lastCloseTime: TimeInterval = 0

    static let log = Logger(subsystem: "com.mujh.DuoBar", category: "panel")
    /// 开发用：面板内容，用来截图。
    var contentView: NSView { host }
    /// 开发用：面板在屏幕上的位置。
    var frame: NSRect { panel.frame }

    init(rootView: some View, appearance: NSAppearance? = nil) {
        host = SizingHostingView(rootView: AnyView(rootView))
        fixedAppearance = appearance
        super.init()
        host.sizingOptions = [.intrinsicContentSize]
        host.onSizeChange = { [weak self] in self?.fitToContent() }

        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // macOS 26 起每块玻璃自己带阴影，窗口不再画一个整体的阴影。
        panel.hasShadow = !Self.floatingGlass
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close(reason: "按了 Esc") }
        panel.contentView = Self.background(containing: host)
    }

    func show(below button: NSStatusBarButton) {
        Self.log.notice("打开面板")
        anchor = button
        panel.appearance = fixedAppearance ?? Self.menuBarAppearance(of: button)
        // 收起动画还没播完又被打开：从当前的样子直接恢复，不再从透明开始。
        let reopening = closing && panel.isVisible
        closing = false
        onShow?()
        host.layoutSubtreeIfNeeded()
        if !reopening {
            panel.setFrame(frame(for: host.fittingSize), display: false)
            panel.alphaValue = 0
        }
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reopening ? 0.2 : 0.12
            panel.animator().alphaValue = 1
        }
        installMonitors()
    }

    func close(reason: String = "其他") {
        guard panel.isVisible, !closing else { return }
        Self.log.notice("收起面板：\(reason, privacy: .public)")
        lastCloseTime = ProcessInfo.processInfo.systemUptime
        closing = true
        removeMonitors()
        onWillClose?()
        // 胶囊合拢、面板缩小的同时淡出；淡出先慢后快，合拢的过程看得见。
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.12 : Self.closeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // 淡出期间又被打开了，就不再收起。
                guard let self, self.closing else { return }
                self.panel.orderOut(nil)
                self.closing = false
                self.onClose?()
            }
        }
    }

    /// 和系统的菜单栏菜单、控制中心一样，深浅跟着菜单栏走：壁纸深、菜单栏是白字时，面板也用深色外观。
    /// 系统本身是浅色模式也一样。
    private static func menuBarAppearance(of button: NSStatusBarButton) -> NSAppearance? {
        switch button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark]) {
        case .darkAqua?, .vibrantDark?: NSAppearance(named: .darkAqua)
        case .aqua?, .vibrantLight?: NSAppearance(named: .aqua)
        default: nil
        }
    }

    // MARK: - 位置和大小

    /// 贴着菜单栏，左边和图标对齐，不超出屏幕。
    private func frame(for size: NSSize) -> NSRect {
        guard let button = anchor, let window = button.window else {
            return NSRect(origin: panel.frame.origin, size: size)
        }
        let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? icon
        let margin: CGFloat = 6
        // 每块各自是玻璃时，四周留着透明边（见 PanelView）：窗口贴着菜单栏，往左让出这条边，玻璃和图标左边对齐。
        let inset = Self.floatingGlass ? Self.floatingInset : 0
        let top = min(icon.minY, visible.maxY) - (Self.floatingGlass ? 0 : 5)
        let x = min(max(icon.minX - inset, visible.minX + margin - inset), visible.maxX - size.width - margin + inset)
        let height = min(size.height, top - visible.minY - margin)
        return NSRect(x: x, y: top - height, width: size.width, height: height)
    }

    /// 内容变高变矮时跟着改大小，顶边不动。
    private func fitToContent() {
        guard panel.isVisible else { return }
        let target = frame(for: host.fittingSize)
        guard target != panel.frame else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(target, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        }
    }

    /// macOS 26 起和控制中心一样：窗口本身透明，里面的胶囊、详情和按钮各自是一块玻璃，直接浮在桌面上。
    /// 玻璃叠在玻璃上会发白发雾，也不会跟着背后的颜色切换文字的深浅，所以不再垫一整块底板。
    static var floatingGlass: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    /// 玻璃四周留给阴影和高光的透明边；上边只留 floatingTopInset，玻璃离菜单栏近一些。
    static let floatingInset: CGFloat = 10
    static let floatingTopInset: CGFloat = 6

    private static func background(containing content: NSView) -> NSView {
        if floatingGlass {
            return content
        }
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(radius: cornerRadius)
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }

    /// 圆角遮罩，四个角不拉伸。
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: - 自动收起

    // 只监听鼠标点击，不需要辅助功能权限。
    private func installMonitors() {
        removeMonitors()
        // 其他 App 的窗口、桌面、别的菜单栏图标。
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isOnAnchor(NSEvent.mouseLocation) else { return }
                self.close(reason: "点了面板外面")
            }
        }
        // DuoBar 自己的其他窗口，比如设置窗口。点菜单栏图标由图标自己的动作来开关。
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel, !self.isOnAnchor(NSEvent.mouseLocation) else { return }
                self.close(reason: "点了 DuoBar 的其他窗口")
            }
            return event
        }
    }

    /// 点在菜单栏图标上：开关交给图标自己的动作，自动收起的逻辑不管。
    private func isOnAnchor(_ screenPoint: NSPoint) -> Bool {
        guard let button = anchor, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(screenPoint)
    }

    /// 这一下点击是否已经让面板收起了，比如按下时面板先失去了焦点；这时图标的动作就不要再把它打开。
    func wasClosed(by event: NSEvent?) -> Bool {
        guard let event else { return false }
        return lastCloseTime >= event.timestamp - 0.05
    }

    private func removeMonitors() {
        for monitor in [outsideClickMonitor, localClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        outsideClickMonitor = nil
        localClickMonitor = nil
    }

    /// 用 ⌘Tab 切到别的 App 等情况下，面板不再是键盘焦点，这时收起。
    func windowDidResignKey(_ notification: Notification) {
        // 按下菜单栏图标时面板也会失去焦点，这时由图标的动作来开关，不然会先收起再被重新打开。
        if NSEvent.pressedMouseButtons != 0, isOnAnchor(NSEvent.mouseLocation) { return }
        close(reason: "失去焦点")
    }
}

/// 可以在不激活 DuoBar 的情况下成为键盘焦点，这样 Esc 能收起面板。
final class MenuPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// SwiftUI 内容的理想大小变了时通知外面，面板据此改大小。
final class SizingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?
    private var pending = false

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // 同一轮里多次变化只处理一次。
        guard !pending else { return }
        pending = true
        Task { @MainActor [weak self] in
            self?.pending = false
            self?.onSizeChange?()
        }
    }
}
