import SwiftUI

/// 面板里展开的一块详情。
enum PanelTab: Hashable, Sendable {
    /// 某个位置显示的内容。
    case slot(Slot)
    /// 网络不在图标上时，单独的 Wi-Fi 控制。
    case wifi
}

/// 点击菜单栏图标后弹出的面板，样子和 macOS 26 的控制中心、菜单栏菜单一致：
/// 平时是几个控制中心样式的胶囊，点其中一个就收起其他的，下面展开系统菜单样式的详情。
///
/// 打开时胶囊从同一个位置滑开，里面的三合一图标跟着拆开：外圈、中间和圆点各自落进一个胶囊的圆形图标里，
/// 和 iPhone Duo 打开控制中心时一样。macOS 26 起胶囊是玻璃，滑开时像一滴水分成几滴。
struct PanelView: View {
    let model: AppModel
    /// 仅用于渲染预览：展开的详情。
    var previewTab: PanelTab?
    /// 仅用于渲染预览：固定的拆分进度，0 是合体，1 是拆开。
    var previewSplit: CGFloat?
    @State private var selectedTab: PanelTab?
    @State private var split = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tab: PanelTab? { previewTab ?? selectedTab }

    private var splitProgress: CGFloat {
        if let previewSplit { return previewSplit }
        if previewTab != nil { return 1 }
        return split ? 1 : 0
    }

    /// 从上到下：外圈、中间、底部圆点。
    private let slotOrder: [Slot] = [.ring, .center, .dots]
    private static let tileSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 玻璃挨得比这更近就会连在一起；胶囊停下时隔 8 点，是分开的。
            TileGlassContainer(spacing: 6) {
                VStack(spacing: Self.tileSpacing) {
                    ForEach(Array(tabs.enumerated()), id: \.element) { index, item in
                        if tab == nil || tab == item {
                            SplitSlide(progress: splitProgress, index: index,
                                       step: ModuleTile<EmptyView>.height + Self.tileSpacing) { reveal, progress in
                                tile(item, reveal: reveal, progress: progress)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if let tab {
                detail(tab)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let release = model.availableUpdate {
                MenuDivider()
                updateRow(release)
            }
            MenuDivider()
            MenuItem(title: "DuoBar 设置…") { model.openSettings() }
            MenuItem(title: "退出 DuoBar") { NSApp.terminate(nil) }
        }
        .padding(.bottom, 6)
        .frame(width: MenuMetrics.width, alignment: .top)
        .onChange(of: model.panelVisible, initial: true) { _, visible in
            guard previewTab == nil, previewSplit == nil else { return }
            if visible {
                if reduceMotion {
                    split = true
                } else {
                    withAnimation(.spring(duration: 0.65, bounce: 0.2).delay(0.05)) { split = true }
                }
            } else {
                // 下次打开时重新从合体开始，也回到只有胶囊的样子。
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selectedTab = nil
                    split = false
                }
            }
        }
        .onChange(of: showsBatteryDetail, initial: true) { _, visible in
            model.batteryDetailVisible = visible
        }
    }

    /// 要显示的胶囊：图标上有的位置，网络不在图标上时再加一个 Wi-Fi。
    private var tabs: [PanelTab] {
        var result = slotOrder.filter { model.layout[$0] != nil }.map(PanelTab.slot)
        if showsWiFiControls, !model.layout.metricKinds.contains(.network) {
            result.append(.wifi)
        }
        return result
    }

    private var showsWiFiControls: Bool {
        model.showWiFiControls && model.network.hasWiFiHardware
    }

    private var showsBatteryDetail: Bool {
        guard case let .slot(slot) = tab else { return false }
        return model.layout[slot] == .metric(.battery)
    }

    private func toggle(_ target: PanelTab) {
        withAnimation(.snappy(duration: 0.3)) {
            selectedTab = selectedTab == target ? nil : target
        }
    }

    // MARK: - 胶囊

    /// 胶囊上的文字、图标状态，以及点圆形图标能做的事。
    private struct TileInfo {
        var title: String
        var subtitle: String
        var active = false
        var tint: Color?
        var iconAction: (() -> Void)?
        var iconHelp: String?
    }

    @ViewBuilder
    private func tile(_ item: PanelTab, reveal: Double, progress: CGFloat) -> some View {
        switch item {
        case .wifi:
            // 不是三合一图标的一部分，等胶囊滑到位再出现。
            let info = networkInfo(title: "Wi-Fi")
            ModuleTile(title: info.title, subtitle: info.subtitle, active: info.active, tint: info.tint,
                       expanded: tab == item, reveal: reveal, iconAction: info.iconAction, iconHelp: info.iconHelp,
                       action: { toggle(item) }) {
                SymbolGlyph(name: model.network.wifiPowered ? "wifi" : "wifi.slash",
                            variable: model.network.wifiAssociated ? Double(max(model.network.signalLevel, 1)) / 4 : nil)
                    .opacity(reveal)
            }
        case let .slot(slot):
            if let content = model.layout[slot] {
                let info = info(for: content)
                ModuleTile(title: info.title, subtitle: info.subtitle, active: info.active, tint: info.tint,
                           expanded: tab == item, reveal: reveal, iconAction: info.iconAction, iconHelp: info.iconHelp,
                           action: { toggle(item) }) {
                    DuoPartGlyph(slot: slot, state: model.iconState, progress: progress,
                                 color: info.active ? Color.fixedLight(info.tint ?? .accentColor) : .primary,
                                 onWhite: info.active)
                        .frame(width: 36, height: 36)
                }
            }
        }
    }

    private func info(for content: SlotContent) -> TileInfo {
        switch content {
        case .metric(.network): return networkInfo(title: model.network.link == .ethernet ? "网络" : "Wi-Fi")
        case .metric(.battery): return batteryInfo
        case .metric(.volume): return volumeInfo
        case let .metric(kind): return TileInfo(title: kind.title, subtitle: model.reading(kind).value)
        case .indicators: return indicatorsInfo
        }
    }

    private func networkInfo(title: String) -> TileInfo {
        let network = model.network
        let canToggle = network.hasWiFiHardware && network.link != .ethernet
        return TileInfo(
            title: title, subtitle: network.headline,
            active: network.link != .none && network.link != .other || network.wifiAssociated,
            iconAction: canToggle ? { model.setWiFiPower(!network.wifiPowered) } : nil,
            iconHelp: network.wifiPowered ? "关闭 Wi-Fi" : "打开 Wi-Fi"
        )
    }

    private var batteryInfo: TileInfo {
        let battery = model.battery
        let tint: Color? = if battery.lowPowerMode { .yellow } else if battery.power != .battery { .green }
            else if battery.isLow { .red } else { nil }
        return TileInfo(title: battery.hasBattery ? "电池" : "电源", subtitle: battery.summary(limit: model.chargeLimit),
                        active: battery.power != .battery, tint: tint)
    }

    private var volumeInfo: TileInfo {
        let muted = model.indicatorStates[.muted] == true
        return TileInfo(title: "声音", subtitle: model.reading(.volume).value, active: !muted,
                        iconAction: { model.setMuted(!muted) }, iconHelp: muted ? "取消静音" : "静音")
    }

    private var indicatorsInfo: TileInfo {
        let kinds = model.layout.indicators.compactMap { $0 }
        let lit = kinds.filter { model.indicatorStates[$0] == true }
        return TileInfo(title: "指示灯", subtitle: lit.isEmpty ? "都没有亮" : lit.map(\.title).joined(separator: "、"),
                        active: !lit.isEmpty)
    }

    // MARK: - 展开的详情

    @ViewBuilder
    private func detail(_ tab: PanelTab) -> some View {
        switch tab {
        case .wifi:
            WiFiSection(model: model)
        case let .slot(slot):
            switch model.layout[slot] {
            case .metric(.network): networkDetail
            case .metric(.battery): BatteryDetail(model: model)
            case .metric(.volume): VolumeDetail(model: model)
            case let .metric(kind): metricDetail(kind)
            case .indicators: indicatorDetail
            case nil: EmptyView()
            }
        }
    }

    @ViewBuilder
    private var networkDetail: some View {
        if showsWiFiControls {
            WiFiSection(model: model)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                MenuTitleRow(title: "网络") { EmptyView() }
                ForEach(model.reading(.network).rows, id: \.label) { MenuValueRow(label: $0.label, value: $0.value) }
                if model.network.wifiAssociated {
                    ssidRow
                }
                MenuDivider()
                MenuItem(title: "网络设置…") { model.openSystemSettings(.network) }
            }
        }
    }

    @ViewBuilder
    private var ssidRow: some View {
        if let ssid = model.network.ssid {
            MenuValueRow(label: "Wi-Fi 名称", value: ssid)
        } else {
            MenuItem(title: model.ssidAccess == .denied ? "去开启定位权限，显示 Wi-Fi 名称…" : "显示 Wi-Fi 名称…") {
                model.requestSSIDAccess()
            }
            .help("macOS 只把 Wi-Fi 名称提供给有定位权限的 App，DuoBar 不会读取你的位置。")
        }
    }

    private func metricDetail(_ kind: MetricKind) -> some View {
        let reading = model.reading(kind)
        return VStack(alignment: .leading, spacing: 0) {
            MenuTitleRow(title: kind.title) {
                Text(reading.value)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ForEach(reading.rows, id: \.label) { MenuValueRow(label: $0.label, value: $0.value) }
            if let action = action(for: kind) {
                MenuDivider()
                MenuItem(title: action.title, action: action.run)
            }
        }
    }

    private func action(for kind: MetricKind) -> (title: String, run: () -> Void)? {
        switch kind {
        case .cpu, .gpu, .memory, .throughput: ("活动监视器…", { model.openActivityMonitor() })
        case .disk: ("存储空间…", { model.openSystemSettings(.storage) })
        case .accessory: ("蓝牙设置…", { model.openSystemSettings(.bluetooth) })
        case .battery, .network, .volume: nil
        }
    }

    private var indicatorDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuTitleRow(title: "指示灯") { EmptyView() }
            ForEach(Array(model.layout.indicators.enumerated()), id: \.offset) { _, kind in
                if let kind {
                    let on = model.indicatorStates[kind] == true
                    MenuRow(title: kind.title, help: kind.summary) {
                        IconCircle(active: on, tint: on && model.indicatorColors ? kind.tint?.color : nil) {
                            IndicatorIcon(kind: kind, size: 12)
                        }
                    } trailing: {
                        indicatorControl(kind)
                    }
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
            .controlSize(.small)
            .labelsHidden()
            .disabled(model.wifiSwitching)
        case .muted:
            Toggle("静音", isOn: Binding(
                get: { model.indicatorStates[.muted] == true },
                set: { model.setMuted($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        case .bluetooth where model.bluetoothAccess == .denied:
            Button("开启权限") { model.requestBluetoothAccess() }
                .controlSize(.small)
        default:
            Text(model.indicatorText(kind))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 更新

    private func updateRow(_ release: ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuRow(title: "DuoBar \(release.version) 可以更新", subtitle: updateProgress ?? "查看更新内容",
                    action: updateProgress == nil ? { model.openReleasePage() } : nil) {
                IconCircle(symbol: "arrow.down", active: true)
            } trailing: {
                if updateProgress != nil {
                    ProgressView()
                        .controlSize(.small)
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
                MenuNote(text: message, color: .red)
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
}

// MARK: - 电池

/// 和系统电池菜单一样：电量、电源、充电状态、立即充满电、能耗模式、使用大量能耗的 App。
private struct BatteryDetail: View {
    let model: AppModel

    var body: some View {
        let battery = model.battery
        VStack(alignment: .leading, spacing: 0) {
            MenuTitleRow(title: battery.hasBattery ? "电池" : "电源") {
                if battery.hasBattery {
                    Text("\(battery.percent)%")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            MenuNote(text: battery.powerSourceText)
            ForEach(battery.statusLines(limit: model.chargeLimit), id: \.self) { MenuNote(text: $0) }
            if model.chargeLimit?.canOverride == true, battery.power != .battery {
                MenuItem(title: model.chargingToFullRequested ? "正在请求充满电…" : "立即充满电",
                         enabled: !model.chargingToFullRequested) {
                    model.chargeToFullNow()
                }
                .padding(.top, 2)
            }
            if let message = model.chargeMessage {
                MenuNote(text: message, color: .red)
            }

            MenuDivider()
            MenuSectionHeader(title: "能耗模式")
            MenuRow(title: battery.energyModeText, subtitle: "在电池设置中更改",
                    help: "macOS 只允许系统自己切换能耗模式",
                    action: { model.openSystemSettings(.battery) }) {
                IconCircle(symbol: energySymbol, active: battery.lowPowerMode || battery.highPowerMode,
                           tint: battery.lowPowerMode ? .yellow : nil)
            } trailing: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if battery.hasBattery {
                MenuDivider()
                MenuSectionHeader(title: "使用大量能耗")
                energyApps
            }

            MenuDivider()
            MenuItem(title: battery.hasBattery ? "电池设置…" : "能耗设置…") {
                model.openSystemSettings(.battery)
            }
        }
    }

    private var energySymbol: String {
        if model.battery.highPowerMode { return "gauge.with.dots.needle.100percent" }
        return model.battery.lowPowerMode ? "gauge.with.dots.needle.0percent" : "gauge.with.dots.needle.50percent"
    }

    @ViewBuilder
    private var energyApps: some View {
        if let hogs = model.energyHogs {
            if hogs.isEmpty {
                MenuNote(text: "没有使用大量能耗的 App")
            } else {
                ForEach(hogs) { hog in
                    MenuRow(title: hog.name, help: "最近平均占用 \(Int(hog.cpu.rounded()))% CPU",
                            action: { model.activate(hog) }) {
                        if let icon = NSRunningApplication(processIdentifier: hog.pid)?.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 22, height: 22)
                        }
                    }
                }
            }
        } else {
            MenuNote(text: "正在统计…")
        }
    }
}

// MARK: - 声音

/// 音量滑块。拖动时先用本地的值，松手后再跟随系统读数，避免滑块来回跳。
private struct VolumeDetail: View {
    let model: AppModel
    @State private var dragging: Double?

    var body: some View {
        let reading = model.reading(.volume)
        let muted = model.indicatorStates[.muted] == true
        VStack(alignment: .leading, spacing: 0) {
            MenuTitleRow(title: "声音") {
                Text(muted ? "静音" : "\(Int(((dragging ?? reading.level) * 100).rounded()))%")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { dragging ?? reading.level },
                    set: { value in
                        dragging = value
                        model.setVolume(value)
                    }
                ), in: 0 ... 1) { editing in
                    if !editing { dragging = nil }
                }
                .controlSize(.small)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, MenuMetrics.inset)
            .padding(.vertical, 4)
            if let device = reading.rows.first(where: { $0.label == "输出设备" })?.value {
                MenuSectionHeader(title: "输出")
                MenuRow(title: device) {
                    IconCircle(symbol: "hifispeaker.fill", active: true)
                }
            }
            MenuDivider()
            MenuItem(title: "声音设置…") { model.openSystemSettings(.sound) }
        }
    }
}

/// 拆分动画里的一个胶囊：跟着进度从第一个胶囊的位置滑到自己的位置。
/// 每一帧都拿到实际的进度，所以文字和圆底可以等胶囊快分开了再出现，不会和上面的胶囊叠在一起。
private struct SplitSlide<Content: View>: View, Animatable {
    var progress: CGFloat
    var index: Int
    /// 相邻两个胶囊的距离。
    var step: CGFloat
    @ViewBuilder var content: (_ reveal: Double, _ progress: CGFloat) -> Content

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        content(index == 0 ? 1 : Double(smoothstep(0.45, 0.95, progress)), progress)
            // 拆分前所有胶囊都叠在第一个的位置。
            .offset(y: -CGFloat(index) * step * (1 - progress))
    }
}
