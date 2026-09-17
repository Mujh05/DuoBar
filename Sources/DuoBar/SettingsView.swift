import AppKit
import SwiftUI

/// 设置窗口：选择三个位置显示什么、拖动交换位置，以及颜色和其他选项。
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var dropTarget: String?

    var body: some View {
        Form {
            layoutSection
            colorSection
            metricsSection
            indicatorsSection
            menuBarSection
            Section("通用") {
                Toggle("登录时自动启动", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let note = model.loginItemNote {
                    Button(note) { model.openLoginItemsSettings() }
                        .buttonStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 图标布局

    private var layoutSection: some View {
        Section {
            IconPreview(state: model.iconState,
                        percent: model.battery.hasBattery ? model.battery.percent : nil,
                        percentMode: model.percentMode,
                        percentTitle: model.percentTitle)
            ForEach(Slot.allCases) { slot in
                slotRow(slot)
                if slot == .dots, model.layout.usesIndicators {
                    ForEach(0 ..< IconLayout.dotCount, id: \.self) { index in
                        dotRow(index)
                    }
                }
            }
        } header: {
            Text("图标布局")
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                Text("按住一行拖到另一行上，可以交换两个位置（或两个圆点）的内容。")
                Spacer()
                Button("恢复默认") { model.resetLayout() }
                    .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func slotRow(_ slot: Slot) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            SlotDiagram(slot: slot)
                .frame(width: 26, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title)
                Text(slot.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Picker(slot.title, selection: Binding(
                get: { model.layout[slot] },
                set: { model.setContent($0, for: slot) }
            )) {
                if model.layout.canClear(slot) {
                    Text("不显示").tag(SlotContent?.none)
                    Divider()
                }
                ForEach(MetricKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(SlotContent?.some(.metric(kind)))
                }
                if slot == .dots {
                    Divider()
                    Label(SlotContent.indicators.title, systemImage: SlotContent.indicators.symbol)
                        .tag(SlotContent?.some(.indicators))
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 2)
        .dragRow(id: "slot:\(slot.rawValue)", target: $dropTarget,
                 preview: model.layout[slot]?.title ?? "不显示") { source in
            guard source.hasPrefix("slot:"), let raw = Int(source.dropFirst(5)),
                  let from = Slot(rawValue: raw), from != slot
            else { return false }
            return withAnimation(.snappy) { model.swapSlots(from, slot) }
        }
    }

    private func dotRow(_ index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            DotDiagram(index: index)
                .frame(width: 26, height: 16)
            Text("圆点 \(index + 1)")
            Spacer(minLength: 12)
            if let kind = model.layout.indicators[index] {
                StatusDot(on: model.indicatorStates[kind] == true,
                          tint: model.indicatorColors ? kind.tint : nil)
            }
            Picker("圆点 \(index + 1)", selection: Binding(
                get: { model.layout.indicators[index] },
                set: { model.setIndicator($0, atDot: index) }
            )) {
                Text("空着").tag(IndicatorKind?.none)
                Divider()
                ForEach(IndicatorKind.allCases) { kind in
                    if let symbol = kind.symbol {
                        Label(kind.title, systemImage: symbol).tag(IndicatorKind?.some(kind))
                    } else {
                        Text(kind.title).tag(IndicatorKind?.some(kind))
                    }
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.leading, 38)
        .dragRow(id: "dot:\(index)", target: $dropTarget,
                 preview: model.layout.indicators[index]?.title ?? "空着") { source in
            guard source.hasPrefix("dot:"), let from = Int(source.dropFirst(4)), from != index else { return false }
            withAnimation(.snappy) { model.swapIndicators(from, index) }
            return true
        }
    }

    // MARK: - 颜色

    private var colorSection: some View {
        Section {
            Toggle(isOn: $model.batteryColors) {
                Text("电量变色")
                Text("低电量模式时黄色；电量不高于 20% 且没接电源时红色。")
            }
            Toggle(isOn: $model.chargingGreen) {
                Text("接着电源时显示绿色")
            }
            .disabled(!model.batteryColors)
            Toggle(isOn: $model.indicatorColors) {
                Text("指示灯亮起时用各自的颜色")
                Text("比如蓝牙蓝色、麦克风橙色、静音红色。")
            }
        } header: {
            Text("颜色")
        } footer: {
            Text("图标带颜色时不再是系统的模板图像，DuoBar 会按菜单栏的深浅自己选择黑色或白色。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 状态列表

    private var metricsSection: some View {
        Section {
            ForEach(MetricKind.allCases) { kind in
                metricRow(kind)
            }
        } header: {
            Text("可显示的状态")
        } footer: {
            Text("右键点一行，可以直接把它放到某个位置。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metricRow(_ kind: MetricKind) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(kind.title)
                    ForEach(model.layout.slots(showing: kind)) { slot in
                        Badge(text: slot.title)
                    }
                }
                Text(kind.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(model.reading(kind).value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            ForEach(Slot.allCases) { slot in
                Button("显示在\(slot.title)") { model.setContent(.metric(kind), for: slot) }
            }
        }
    }

    private var indicatorsSection: some View {
        Section {
            ForEach(IndicatorKind.allCases) { kind in
                indicatorRow(kind)
            }
        } header: {
            Text("可用的指示灯")
        } footer: {
            Text("底部圆点选“独立指示灯”后，每个点可以显示下面任意一项，打开时亮、关闭时暗。右键点一行可以直接放到某个圆点。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func indicatorRow(_ kind: IndicatorKind) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IndicatorIcon(kind: kind)
                .foregroundStyle(kind.tint.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(kind.title)
                    ForEach(model.layout.dots(showing: kind), id: \.self) { index in
                        Badge(text: "圆点 \(index + 1)")
                    }
                }
                Text(kind.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                StatusDot(on: model.indicatorStates[kind] == true,
                          tint: model.indicatorColors ? kind.tint : nil)
                Text(model.indicatorText(kind))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            ForEach(0 ..< IconLayout.dotCount, id: \.self) { index in
                Button("显示在圆点 \(index + 1)") { model.showIndicator(kind, atDot: index) }
            }
        }
    }

    // MARK: - 菜单栏

    private var menuBarSection: some View {
        Section("菜单栏") {
            Picker("电量百分比", selection: $model.percentMode) {
                ForEach(PercentMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if model.percentMode == .onRing, model.layout[.ring] == nil {
                Text("“圆环顶部”需要先在图标布局中显示外圈圆环。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent {
                Label("⌘ 拖动", systemImage: "arrow.left.and.right")
                    .foregroundStyle(.secondary)
            } label: {
                Text("图标位置")
                Text("按住 ⌘，把菜单栏里的 DuoBar 图标拖到控制中心左边。macOS 会记住你放置的位置。")
            }
            LabeledContent {
                Button("打开菜单栏设置…") { model.openMenuBarSettings() }
            } label: {
                Text("隐藏系统自带的 Wi-Fi 和电池图标")
                Text("macOS 不允许其他 App 移除系统图标，需要在“系统设置 › 菜单栏”里把它们关掉。")
            }
        }
    }
}

// MARK: - 拖动交换

private extension View {
    /// 整行可以拖到另一行上；onDrop 收到被拖动那一行的 id。
    func dragRow(id: String, target: Binding<String?>, preview: String,
                 onDrop: @escaping (String) -> Bool) -> some View {
        let prefix = "duobar-"
        return contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(target.wrappedValue == id ? Color.accentColor.opacity(0.15) : .clear)
                    .padding(-4)
            )
            .draggable(prefix + id) {
                Text(preview).padding(6)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first, item.hasPrefix(prefix) else { return false }
                return onDrop(String(item.dropFirst(prefix.count)))
            } isTargeted: { targeted in
                if targeted {
                    target.wrappedValue = id
                } else if target.wrappedValue == id {
                    target.wrappedValue = nil
                }
            }
    }
}

// MARK: - 小部件

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
    }
}

/// 当前布局的预览：放大版，以及菜单栏里的实际大小（浅色和深色菜单栏各一条）。
private struct IconPreview: View {
    let state: IconState
    let percent: Int?
    let percentMode: PercentMode
    let percentTitle: String?

    private var embeddedPercent: Int? {
        state.ring == nil ? nil : percent
    }

    private var embeddedProgress: CGFloat {
        percentMode == .onRing && embeddedPercent != nil ? 1 : 0
    }

    var body: some View {
        HStack(spacing: 24) {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                context.draw(DuoParts.combined(state, center: center, radius: size.height / 2.5,
                                               style: .reference,
                                               embeddedPercent: embeddedPercent,
                                               embeddedPercentProgress: embeddedProgress),
                             color: .primary)
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 8) {
                menuBarSample(dark: false)
                menuBarSample(dark: true)
                Text("菜单栏里的实际大小")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func menuBarSample(dark: Bool) -> some View {
        HStack(spacing: 2) {
            if let percentTitle {
                Text(percentTitle)
                    .font(.system(size: 13).monospacedDigit())
            }
            Canvas { context, size in
                let offset = MenuBarIcon.center.y - MenuBarIcon.size.height / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2 + offset)
                context.draw(DuoParts.combined(state, center: center, radius: MenuBarIcon.radius,
                                               style: .menuBar,
                                               embeddedPercent: embeddedPercent,
                                               embeddedPercentProgress: embeddedProgress),
                             color: dark ? .white : .black.opacity(0.85))
            }
            .frame(width: MenuBarIcon.size.width, height: MenuBarIcon.size.height)
        }
        .foregroundStyle(dark ? .white : .black.opacity(0.85))
        .frame(width: 120, height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(dark ? Color(white: 0.15) : Color(white: 0.92)))
        // 让系统颜色按这条菜单栏的深浅取值。
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

/// 设置里每一行左边的小图：高亮这一行对应的位置。
private struct SlotDiagram: View {
    let slot: Slot

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2.35
            context.draw(DuoParts.diagram(highlight: slot, center: center, radius: radius, style: .menuBar),
                         color: .primary)
        }
    }
}

/// 4 个圆点里高亮第 index 个，排成和图标底部一样的弧形。
private struct DotDiagram: View {
    let index: Int

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0 ..< IconLayout.dotCount, id: \.self) { i in
                Circle()
                    .fill(Color.primary.opacity(i == index ? 1 : 0.2))
                    .frame(width: 4.5, height: 4.5)
                    .offset(y: i == 0 || i == IconLayout.dotCount - 1 ? -1.5 : 1.5)
            }
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "DuoBar 设置"
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.contentMinSize = NSSize(width: 460, height: 420)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("DuoBarSettings")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.settingsVisible = false
    }
}
