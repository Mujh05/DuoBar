import SwiftUI

/// 面板里展开的一块详情。
enum PanelTab: Hashable, Sendable {
    /// 某个位置显示的内容。
    case slot(Slot)
    /// 网络不在图标上时，单独的 Wi-Fi 控制。
    case wifi
}

/// 点击菜单栏图标后弹出的面板，样子和 macOS 26 的控制中心、菜单栏菜单一致：
/// 平时是几个控制中心样式的胶囊（见 PanelTiles），点其中一个就收起其他的，下面展开系统菜单样式的详情。
/// 打开时胶囊从同一个位置滑开，三合一图标跟着拆开，和 iPhone Duo 打开控制中心时一样。
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelTiles(model: model, progress: splitProgress, selected: tab, onSelect: toggle)
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
            // 展开了详情时和上面隔一条线；只有胶囊时直接接在下面。
            if tab != nil || model.availableUpdate != nil {
                MenuDivider()
            }
            HStack(spacing: 8) {
                CapsuleButton(title: "设置", symbol: "gearshape", help: "打开 DuoBar 设置") { model.openSettings() }
                CapsuleButton(title: "退出", symbol: "power", help: "退出 DuoBar") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
        }
        .padding(.bottom, 10)
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
                    IndicatorRow(model: model, kind: kind)
                }
            }
            MenuDivider()
            MenuItem(title: "选择显示哪些指示灯…") { model.openSettings(page: .indicators) }
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

// MARK: - 指示灯

/// 指示灯的一行：点整行打开对应的设置（VPN 打开 VPN 设置，内存紧张打开活动监视器）；
/// Wi-Fi 和静音在右边另有开关，可以直接开关。
private struct IndicatorRow: View {
    let model: AppModel
    let kind: IndicatorKind

    var body: some View {
        let on = model.indicatorStates[kind] == true
        HStack(spacing: 9) {
            Button {
                model.openSettings(for: kind)
            } label: {
                HStack(spacing: 9) {
                    IconCircle(active: on, tint: on && model.indicatorColors ? kind.tint?.color : nil) {
                        IndicatorIcon(kind: kind, size: 12)
                    }
                    Text(kind.title)
                        .font(.system(size: 13))
                    Spacer(minLength: 8)
                    if !hasSwitch, !needsPermission {
                        Text(model.indicatorText(kind))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(kind.summary)点一下打开“\(kind.settingsTitle)”。")
            control
        }
        .frame(minHeight: 32)
        .menuRowHighlight()
    }

    private var hasSwitch: Bool {
        (kind == .wifi && model.network.hasWiFiHardware) || kind == .muted
    }

    private var needsPermission: Bool {
        kind == .bluetooth && model.bluetoothAccess == .denied
    }

    @ViewBuilder
    private var control: some View {
        if kind == .wifi, hasSwitch {
            Toggle("Wi-Fi", isOn: Binding(
                get: { model.network.wifiPowered },
                set: { model.setWiFiPower($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .disabled(model.wifiSwitching)
        } else if kind == .muted {
            Toggle("静音", isOn: Binding(
                get: { model.indicatorStates[.muted] == true },
                set: { model.setMuted($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        } else if needsPermission {
            Button("开启权限") { model.requestBluetoothAccess() }
                .controlSize(.small)
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
