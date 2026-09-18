import SwiftUI

/// 面板里展开的一块详情。
enum PanelTab: Hashable, Sendable {
    /// 某个位置显示的内容。
    case slot(Slot)
    /// 网络不在图标上时，从底部按钮打开的 Wi-Fi 控制。
    case wifi
}

/// 点击菜单栏图标后弹出的面板。打开时三合一图标会拆成三个独立图标，和 iPhone Duo 打开控制中心时一样；
/// 平时只显示这三个图标，点其中一个才展开它的详情和相应的设置，保持面板紧凑。
struct PanelView: View {
    let model: AppModel
    /// 仅用于渲染预览：固定为拆开或合体，不播放动画。
    var previewSplit: Bool?
    /// 仅用于渲染预览：展开的详情。
    var previewTab: PanelTab?
    @State private var animatedSplit = false
    @State private var selectedTab: PanelTab?
    @State private var hoveredSlot: Slot?

    private var split: Bool { previewSplit ?? animatedSplit }
    private var tab: PanelTab? { previewTab ?? selectedTab }

    /// 拆开后的顺序：底部圆点在左，中间在中，外圈在右。
    private let slotOrder: [Slot] = [.dots, .center, .ring]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)
            if let tab, hasContent(tab) {
                Divider()
                detail(tab)
                    .padding(.vertical, 12)
            }
            if let release = model.availableUpdate {
                Divider()
                updateBanner(release)
                    .padding(.vertical, 10)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
        .onChange(of: model.panelVisible, initial: true) { _, visible in
            guard previewSplit == nil else { return }
            if visible {
                withAnimation(.spring(duration: 0.75, bounce: 0.22).delay(0.12)) { animatedSplit = true }
            } else {
                // 下次打开时重新从合体开始，详情也收起来。
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    animatedSplit = false
                    selectedTab = nil
                }
            }
        }
    }

    // MARK: - 顶部：可以点的三个图标

    private var header: some View {
        VStack(spacing: 8) {
            SplitGlyphView(progress: split ? 1 : 0, state: model.iconState)
                .frame(height: 72)
            HStack(spacing: 0) {
                ForEach(slotOrder) { caption($0) }
            }
            .opacity(split ? 1 : 0)
            .animation(.easeOut(duration: 0.3).delay(split ? 0.35 : 0), value: split)
        }
        .padding(.vertical, 6)
        .background(slotHighlights)
        .overlay(slotButtons)
    }

    private var slotHighlights: some View {
        HStack(spacing: 4) {
            ForEach(slotOrder) { slot in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(highlight(slot)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: tab)
        .animation(.easeOut(duration: 0.15), value: hoveredSlot)
    }

    private func highlight(_ slot: Slot) -> Double {
        if tab == .slot(slot) { return 0.09 }
        if hoveredSlot == slot, canSelect(slot) { return 0.045 }
        return 0
    }

    private var slotButtons: some View {
        HStack(spacing: 4) {
            ForEach(slotOrder) { slot in
                Button {
                    toggle(.slot(slot))
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSelect(slot))
                .onHover { inside in
                    if inside {
                        hoveredSlot = slot
                    } else if hoveredSlot == slot {
                        hoveredSlot = nil
                    }
                }
                .help(canSelect(slot) ? "查看\(slotTitle(slot))" : "")
                .accessibilityLabel(slotTitle(slot))
            }
        }
    }

    private func canSelect(_ slot: Slot) -> Bool {
        split && model.layout[slot] != nil
    }

    private func slotTitle(_ slot: Slot) -> String {
        model.layout[slot]?.title ?? slot.title
    }

    private func toggle(_ target: PanelTab) {
        withAnimation(.snappy(duration: 0.25)) {
            selectedTab = selectedTab == target ? nil : target
        }
    }

    private func hasContent(_ tab: PanelTab) -> Bool {
        switch tab {
        case let .slot(slot): model.layout[slot] != nil
        case .wifi: showsWiFiControls
        }
    }

    private func caption(_ slot: Slot) -> some View {
        let text: (title: String, subtitle: String)? = switch model.layout[slot] {
        case let .metric(kind): (model.reading(kind).value, kind.shortTitle)
        case .indicators: (litSummary, "指示灯亮起")
        case nil: nil
        }
        return VStack(spacing: 2) {
            if let text {
                Text(text.title)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text(text.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(tab == .slot(slot) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    private var litSummary: String {
        let kinds = model.layout.indicators.compactMap { $0 }
        let lit = kinds.filter { model.indicatorStates[$0] == true }.count
        return "\(lit)/\(kinds.count)"
    }

    // MARK: - 展开的详情

    private var showsWiFiControls: Bool {
        model.showWiFiControls && model.network.hasWiFiHardware
    }

    @ViewBuilder
    private func detail(_ tab: PanelTab) -> some View {
        switch tab {
        case .wifi:
            WiFiSection(model: model, summary: networkSummary)
        case let .slot(slot):
            switch model.layout[slot] {
            case let .metric(kind): metricDetail(kind)
            case .indicators: indicatorDetail
            case nil: EmptyView()
            }
        }
    }

    @ViewBuilder
    private func metricDetail(_ kind: MetricKind) -> some View {
        if kind == .network, showsWiFiControls {
            WiFiSection(model: model, summary: networkSummary)
        } else {
            section(kind.title) {
                if kind == .volume {
                    VolumeControl(model: model)
                } else {
                    rows(for: kind)
                }
                if let action = action(for: kind) {
                    Button(action.title, action: action.run)
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                        .padding(.top, 2)
                }
            }
        }
    }

    /// 网络的一行摘要，放在 Wi-Fi 标题下面。
    private var networkSummary: String? {
        let network = model.network
        var parts: [String] = []
        if network.link != .wifi { parts.append(network.linkText) }
        if let signal = network.signalText { parts.append(signal) }
        if let detail = network.detailText { parts.append(detail) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func action(for kind: MetricKind) -> (title: String, run: () -> Void)? {
        switch kind {
        case .battery: ("电池设置…", { model.openSystemSettings(.battery) })
        case .cpu, .gpu, .memory, .throughput: ("打开活动监视器", { model.openActivityMonitor() })
        case .disk: ("存储空间…", { model.openSystemSettings(.storage) })
        case .volume: ("声音设置…", { model.openSystemSettings(.sound) })
        case .accessory: ("蓝牙设置…", { model.openSystemSettings(.bluetooth) })
        case .network: ("网络设置…", { model.openSystemSettings(.network) })
        }
    }

    @ViewBuilder
    private func rows(for kind: MetricKind) -> some View {
        let reading = model.reading(kind)
        ForEach(Array(reading.rows.enumerated()), id: \.offset) { index, item in
            row(item.label, item.value)
            // 网络的第一行是“连接”，Wi-Fi 名称紧跟其后。
            if kind == .network, index == 0, model.network.wifiAssociated {
                ssidRow
            }
        }
    }

    private var ssidRow: some View {
        HStack {
            label("Wi-Fi 名称")
            Spacer(minLength: 12)
            if let ssid = model.network.ssid {
                Text(ssid).font(.system(size: 12))
            } else {
                Button(model.ssidAccess == .denied ? "去开启定位权限" : "显示名称") {
                    model.requestSSIDAccess()
                }
                .controlSize(.small)
                .help("macOS 只把 Wi-Fi 名称提供给有定位权限的 App，DuoBar 不会读取你的位置。")
            }
        }
    }

    private var indicatorDetail: some View {
        section("指示灯") {
            ForEach(Array(model.layout.indicators.enumerated()), id: \.offset) { _, kind in
                if let kind {
                    HStack(spacing: 8) {
                        StatusDot(on: model.indicatorStates[kind] == true,
                                  tint: model.indicatorColors ? kind.tint : nil)
                        label(kind.title)
                        Spacer(minLength: 12)
                        indicatorControl(kind)
                    }
                    .frame(minHeight: 20)
                }
            }
        }
    }

    /// 能直接操作的指示灯给开关，其他的显示状态。
    @ViewBuilder
    private func indicatorControl(_ kind: IndicatorKind) -> some View {
        switch kind {
        case .wifi where model.network.hasWiFiHardware:
            Toggle("Wi-Fi", isOn: Binding(
                get: { model.network.wifiPowered },
                set: { model.setWiFiPower($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .disabled(model.wifiSwitching)
        case .muted:
            Toggle("静音", isOn: Binding(
                get: { model.indicatorStates[.muted] == true },
                set: { model.setMuted($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        case .bluetooth where model.bluetoothAccess == .denied:
            Button("去开启蓝牙权限") { model.requestBluetoothAccess() }
                .controlSize(.small)
        default:
            Text(model.indicatorText(kind))
                .font(.system(size: 12))
        }
    }

    // MARK: - 更新和底部

    private func updateBanner(_ release: ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DuoBar \(release.version) 可以更新")
                        .font(.system(size: 12, weight: .semibold))
                    Button("查看更新内容") { model.openReleasePage() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
                Spacer(minLength: 8)
                if let progress = updateProgress {
                    ProgressView()
                        .controlSize(.small)
                    Text(progress)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Button("立即更新") { model.installUpdate() }
                        .controlSize(.small)
                        .help("下载并校验新版本，替换当前的 DuoBar 后自动重新打开")
                    Button {
                        model.skipUpdate()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("跳过这个版本")
                }
            }
            if let message = model.updateMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var updateProgress: String? {
        switch model.updateStatus {
        case .downloading: "正在下载…"
        case .installing: "正在安装…"
        case .idle, .checking, .upToDate, .available: nil
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("自定义图标…") { model.openSettings() }
            // 网络没放在图标上时，Wi-Fi 控制从这里打开。
            if showsWiFiControls, !model.layout.metricKinds.contains(.network) {
                Button {
                    toggle(.wifi)
                } label: {
                    Image(systemName: model.network.wifiPowered ? "wifi" : "wifi.slash")
                }
                .buttonStyle(.bordered)
                .tint(tab == .wifi ? Color.accentColor : nil)
                .help("Wi-Fi")
            }
            Spacer()
            Button("退出 DuoBar") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
        .padding(.top, 12)
    }

    // MARK: - 小部件

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            label(title)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

/// 音量滑块和静音按钮。拖动时先用本地的值，松手后再跟随系统读数，避免滑块来回跳。
private struct VolumeControl: View {
    let model: AppModel
    @State private var dragging: Double?

    var body: some View {
        let reading = model.reading(.volume)
        let muted = model.indicatorStates[.muted] == true
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    model.setMuted(!muted)
                } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.fill")
                        .frame(width: 16)
                }
                .buttonStyle(.borderless)
                .help(muted ? "取消静音" : "静音")
                Slider(value: Binding(
                    get: { dragging ?? reading.level },
                    set: { value in
                        dragging = value
                        model.setVolume(value)
                    }
                ), in: 0 ... 1) { editing in
                    if !editing { dragging = nil }
                }
                Text(muted ? "静音" : "\(Int(((dragging ?? reading.level) * 100).rounded()))%")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            if let device = reading.rows.first(where: { $0.label == "输出设备" })?.value {
                Text(device)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 指示灯当前是否亮起的小圆点。
struct StatusDot: View {
    let on: Bool
    let tint: DuoTint?

    var body: some View {
        Circle()
            .fill(on ? (tint?.color ?? Color.primary) : Color.secondary.opacity(0.3))
            .frame(width: 7, height: 7)
    }
}
