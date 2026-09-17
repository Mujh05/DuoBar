import AppKit
import Observation
import ServiceManagement

enum PercentMode: String, CaseIterable, Identifiable, Sendable {
    case never, whenLow, always, onRing

    var id: Self { self }

    var title: String {
        switch self {
        case .never: "不显示"
        case .whenLow: "图标左侧（电量低时）"
        case .always: "图标左侧（始终）"
        case .onRing: "圆环顶部"
        }
    }
}

/// 需要定时读取的数据源。电量、网络、蓝牙由系统通知驱动，不在这里。
enum Source: CaseIterable, Sendable {
    case cpu, gpu, memory, disk, throughput, audio, microphone, vpn, displays, keyboard, accessories

    var interval: TimeInterval {
        switch self {
        case .cpu, .gpu, .memory, .throughput: 2
        case .audio, .microphone, .keyboard: 1
        case .vpn, .displays: 3
        case .disk, .accessories: 60
        }
    }
}

extension MetricKind {
    var source: Source? {
        switch self {
        case .battery, .network: nil
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .disk: .disk
        case .throughput: .throughput
        case .volume: .audio
        case .accessory: .accessories
        }
    }
}

extension IndicatorKind {
    var source: Source? {
        switch self {
        case .headphones, .muted: .audio
        case .microphone: .microphone
        case .vpn: .vpn
        case .externalDisplay: .displays
        case .capsLock: .keyboard
        case .memoryPressure: .memory
        case .diskLow: .disk
        case .bluetooth, .wifi, .internet, .hotspot, .ethernet,
             .charging, .pluggedIn, .lowPower, .lowBattery: nil
        }
    }
}

/// 面板里的一节详情。
enum DetailSection: Hashable, Identifiable, Sendable {
    case metric(MetricKind)
    case indicators

    var id: Self { self }
}

@MainActor
@Observable
final class AppModel {
    private(set) var battery = BatteryInfo.placeholder
    private(set) var network = NetworkInfo.placeholder
    private(set) var readings: [MetricKind: MetricReading] = [:]
    /// 指示灯状态；没有记录表示未知。
    private(set) var indicatorStates: [IndicatorKind: Bool] = [:]
    private(set) var bluetoothAccess = BluetoothMonitor.access
    private(set) var ssidAccess = LocationAccess.State.notDetermined
    private(set) var launchAtLogin = false
    private(set) var loginItemNote: String?

    /// 三个位置各显示什么。
    private(set) var layout: IconLayout {
        didSet {
            guard layout != oldValue else { return }
            Self.defaults.set(layout.storageValue, forKey: Keys.layout)
            refreshSources()
            onIconChange?()
        }
    }

    var percentMode: PercentMode {
        didSet { save(percentMode.rawValue, Keys.percentMode) }
    }

    /// 电量变色：低电量模式黄色，20% 以下红色。
    var batteryColors: Bool {
        didSet { save(batteryColors, Keys.batteryColors) }
    }

    /// 电量变色时，接着电源显示绿色。
    var chargingGreen: Bool {
        didSet { save(chargingGreen, Keys.chargingGreen) }
    }

    /// 指示灯亮起时用各自的颜色。
    var indicatorColors: Bool {
        didSet { save(indicatorColors, Keys.indicatorColors) }
    }

    /// 面板是否打开。打开时网络信息刷新得更勤。
    var panelVisible = false {
        didSet {
            networkMonitor.fastPolling = panelVisible
            if panelVisible {
                batteryMonitor.refresh()
                networkMonitor.refresh()
                bluetoothAccess = BluetoothMonitor.access
                refreshLoginItem()
            }
        }
    }

    /// 设置窗口打开时，所有状态都采样，方便对照。
    var settingsVisible = false {
        didSet {
            guard settingsVisible != oldValue else { return }
            refreshSources()
            if settingsVisible { refreshLoginItem() }
        }
    }

    /// 菜单栏图标需要重画时调用。
    @ObservationIgnored var onIconChange: (() -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?

    @ObservationIgnored private let batteryMonitor = BatteryMonitor()
    @ObservationIgnored private let networkMonitor = NetworkMonitor()
    @ObservationIgnored private let bluetoothMonitor = BluetoothMonitor()
    @ObservationIgnored private let location = LocationAccess()
    @ObservationIgnored private var cpuSampler = CPUSampler()
    @ObservationIgnored private var throughputSampler = ThroughputSampler()
    @ObservationIgnored private var activeSources: Set<Source> = []
    @ObservationIgnored private var lastSampled: [Source: TimeInterval] = [:]
    /// 上一次没拿到结果（需要两次采样才能算差值）的数据源。
    @ObservationIgnored private var pending: Set<Source> = []
    @ObservationIgnored private var samplingTask: Task<Void, Never>?

    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let percentMode = "percentMode"
        static let layout = "layout"
        static let batteryColors = "batteryColors"
        static let chargingGreen = "chargingGreen"
        static let indicatorColors = "indicatorColors"
    }

    init() {
        let defaults = Self.defaults
        percentMode = PercentMode(rawValue: defaults.string(forKey: Keys.percentMode) ?? "") ?? .whenLow
        layout = defaults.string(forKey: Keys.layout).flatMap(IconLayout.init(storageValue:)) ?? .standard
        batteryColors = defaults.object(forKey: Keys.batteryColors) as? Bool ?? true
        chargingGreen = defaults.object(forKey: Keys.chargingGreen) as? Bool ?? true
        indicatorColors = defaults.object(forKey: Keys.indicatorColors) as? Bool ?? true
    }

    private func save(_ value: Any, _ key: String) {
        Self.defaults.set(value, forKey: key)
        onIconChange?()
    }

    func start() {
        batteryMonitor.onChange = { [weak self] info in self?.apply(info) }
        networkMonitor.onChange = { [weak self] info in self?.apply(info) }
        bluetoothMonitor.onChange = { [weak self] on in
            self?.bluetoothAccess = BluetoothMonitor.access
            self?.setIndicator(.bluetooth, on)
        }
        location.onChange = { [weak self] state in
            self?.ssidAccess = state
            self?.networkMonitor.refresh()
        }
        ssidAccess = location.state
        batteryMonitor.start()
        networkMonitor.start()
        // 读数和初始占位值相同时不会触发回调，这里先填一次。
        apply(batteryMonitor.info)
        apply(networkMonitor.info)
        refreshSources()
        refreshLoginItem()
    }

    // MARK: - 图标

    var iconState: IconState {
        func part(_ kind: MetricKind) -> IconPart {
            IconPart(kind: kind, reading: reading(kind), tint: tint(for: kind))
        }
        let dots: DotsPart? = switch layout[.dots] {
        case .indicators: .indicators(layout.indicators, states: indicatorStates, colorful: indicatorColors)
        case let .metric(kind): .meter(part(kind))
        case nil: nil
        }
        return IconState(ring: layout.metric(at: .ring).map(part),
                         center: layout.metric(at: .center).map(part),
                         dots: dots)
    }

    private func tint(for kind: MetricKind) -> DuoTint? {
        guard kind == .battery, batteryColors else { return nil }
        return battery.tint(chargingGreen: chargingGreen)
    }

    func reading(_ kind: MetricKind) -> MetricReading {
        readings[kind] ?? .unavailable("正在读取…", value: "…")
    }

    func indicatorText(_ kind: IndicatorKind) -> String {
        if kind == .bluetooth, bluetoothAccess != .granted {
            return "需要蓝牙权限"
        }
        return kind.stateText(indicatorStates[kind])
    }

    /// 面板里按拆开后“左、中、右”的顺序列出正在显示的内容。
    var detailSections: [DetailSection] {
        var seen = Set<DetailSection>()
        return [Slot.dots, .center, .ring].compactMap { slot -> DetailSection? in
            switch layout[slot] {
            case let .metric(kind): .metric(kind)
            case .indicators: .indicators
            case nil: nil
            }
        }
        .filter { seen.insert($0).inserted }
    }

    /// 菜单栏图标左边的百分比文字；nil 表示不显示。
    var percentTitle: String? {
        guard battery.hasBattery else { return nil }
        switch percentMode {
        case .never: return nil
        case .whenLow: return battery.isLow ? "\(battery.percent)%" : nil
        case .always: return "\(battery.percent)%"
        case .onRing: return nil
        }
    }

    var accessibilitySummary: String {
        var parts: [String] = []
        var seen = Set<MetricKind>()
        for slot in Slot.allCases {
            if let kind = layout.metric(at: slot), seen.insert(kind).inserted {
                parts.append("\(kind.shortTitle) \(reading(kind).value)")
            }
        }
        if layout.usesIndicators {
            let lights = layout.indicators.compactMap { $0 }.map { "\($0.title)\(indicatorText($0))" }
            parts.append("指示灯：" + lights.joined(separator: "、"))
        }
        if percentMode == .onRing, layout[.ring] != nil, battery.hasBattery,
           !seen.contains(.battery) {
            parts.insert("电量 \(battery.percent)%", at: 0)
        }
        return parts.joined(separator: "；")
    }

    // MARK: - 布局

    func setContent(_ content: SlotContent?, for slot: Slot) {
        var new = layout
        if new.set(content, at: slot) { layout = new }
    }

    @discardableResult
    func swapSlots(_ a: Slot, _ b: Slot) -> Bool {
        var new = layout
        guard new.swapAt(a, b) else { return false }
        layout = new
        return true
    }

    func setIndicator(_ kind: IndicatorKind?, atDot index: Int) {
        var new = layout
        new.setIndicator(kind, at: index)
        layout = new
    }

    /// 把某个指示灯放到某个圆点上；底部圆点还不是指示灯模式时顺便切过去。
    func showIndicator(_ kind: IndicatorKind, atDot index: Int) {
        var new = layout
        new.set(.indicators, at: .dots)
        new.setIndicator(kind, at: index)
        layout = new
    }

    func swapIndicators(_ a: Int, _ b: Int) {
        var new = layout
        new.swapIndicators(a, b)
        layout = new
    }

    func resetLayout() {
        layout = .standard
    }

    func openSettings() {
        onOpenSettings?()
    }

    /// 打开“系统设置 › 菜单栏”，用户可以在那里隐藏系统自带的 Wi-Fi 和电池图标。
    func openMenuBarSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
    }

    // MARK: - 事件驱动的数据

    private func apply(_ info: BatteryInfo) {
        battery = info
        setReading(.battery, .battery(info))
        setIndicator(.charging, info.power == .charging)
        setIndicator(.pluggedIn, info.power != .battery)
        setIndicator(.lowPower, info.lowPowerMode)
        setIndicator(.lowBattery, info.isLow && info.power == .battery)
        onIconChange?()
    }

    private func apply(_ info: NetworkInfo) {
        network = info
        setReading(.network, .network(info))
        setIndicator(.wifi, info.wifiPowered)
        setIndicator(.internet, info.link != .none)
        setIndicator(.hotspot, info.link == .hotspot)
        setIndicator(.ethernet, info.link == .ethernet)
    }

    private func setReading(_ kind: MetricKind, _ reading: MetricReading) {
        guard readings[kind] != reading else { return }
        readings[kind] = reading
        onIconChange?()
    }

    private func setIndicator(_ kind: IndicatorKind, _ on: Bool?) {
        guard indicatorStates[kind] != on else { return }
        indicatorStates[kind] = on
        onIconChange?()
    }

    // MARK: - 定时采样

    private var neededSources: Set<Source> {
        let metrics = settingsVisible ? Set(MetricKind.allCases) : layout.metricKinds
        let indicators = settingsVisible ? Set(IndicatorKind.allCases) : layout.activeIndicators
        return Set(metrics.compactMap(\.source) + indicators.compactMap(\.source))
    }

    /// 只采样正在显示的内容；布局或设置窗口变化时重新安排。
    private func refreshSources() {
        // 蓝牙：用到“蓝牙”指示灯时才启动；设置窗口里只在已经授权时顺便读一下，不主动弹权限框。
        let wantsBluetooth = layout.activeIndicators.contains(.bluetooth)
            || (settingsVisible && BluetoothMonitor.access == .granted)
        if wantsBluetooth {
            bluetoothMonitor.start()
        } else if bluetoothMonitor.isRunning {
            bluetoothMonitor.stop()
            setIndicator(.bluetooth, nil)
        }

        let sources = neededSources
        guard sources != activeSources || (samplingTask == nil && !sources.isEmpty) else { return }
        // 新加入的差值数据源要重新开始，否则第一次结果会跨越很长一段时间。
        let added = sources.subtracting(activeSources)
        if added.contains(.cpu) { cpuSampler = CPUSampler() }
        if added.contains(.throughput) { throughputSampler = ThroughputSampler() }
        activeSources = sources
        pending.formIntersection(sources)

        samplingTask?.cancel()
        samplingTask = nil
        guard let tick = sources.map(\.interval).min() else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let waiting = self?.sample(sources) else { return }
                // 需要差值的数据源第一次没有结果，半秒后补一次。
                let delay = waiting ? 0.5 : tick
                try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(delay / 4))
            }
        }
    }

    /// 返回 true 表示还有数据源在等第二次采样。
    private func sample(_ sources: Set<Source>) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        for source in sources {
            if !pending.contains(source), let last = lastSampled[source], now - last < source.interval - 0.25 {
                continue
            }
            lastSampled[source] = now
            if read(source) {
                pending.remove(source)
            } else {
                pending.insert(source)
            }
        }
        return !pending.isDisjoint(with: sources)
    }

    /// 返回 false 表示这次还没有结果（需要差值的数据源第一次采样）。读取失败会显示“暂无数据”。
    private func read(_ source: Source) -> Bool {
        switch source {
        case .cpu:
            guard let usage = cpuSampler.sample() else { return false }
            setReading(.cpu, .cpu(usage))
        case .gpu:
            setReading(.gpu, GPUReader.utilization().map(MetricReading.gpu) ?? .unavailable("读不到 GPU 占用"))
        case .memory:
            let sample = MemoryReader.read()
            setReading(.memory, sample.map(MetricReading.memory) ?? .unavailable("读不到内存信息"))
            setIndicator(.memoryPressure, sample.map { $0.pressure >= 2 })
        case .disk:
            let sample = DiskReader.read()
            setReading(.disk, sample.map(MetricReading.disk) ?? .unavailable("读不到磁盘信息"))
            setIndicator(.diskLow, sample.map { $0.total > 0 && Double($0.available) < Double($0.total) * 0.1 })
        case .throughput:
            guard let sample = throughputSampler.sample() else { return false }
            setReading(.throughput, .throughput(sample))
        case .audio:
            let sample = AudioReader.read()
            setReading(.volume, sample.map(MetricReading.volume) ?? .unavailable("没有输出设备"))
            setIndicator(.muted, sample?.muted)
            setIndicator(.headphones, sample?.bluetoothOutput)
        case .microphone:
            setIndicator(.microphone, MicrophoneReader.inUse())
        case .vpn:
            setIndicator(.vpn, VPNReader.isActive())
        case .displays:
            setIndicator(.externalDisplay, DisplayReader.hasExternal())
        case .keyboard:
            setIndicator(.capsLock, NSEvent.modifierFlags.contains(.capsLock))
        case .accessories:
            setReading(.accessory, .accessories(AccessoryReader.read()))
        }
        return true
    }

    // MARK: - 权限

    func requestBluetoothAccess() {
        switch BluetoothMonitor.access {
        case .notDetermined:
            bluetoothMonitor.start()
        case .denied:
            openPrivacySettings("Privacy_Bluetooth")
        case .granted:
            bluetoothAccess = .granted
        }
    }

    func requestSSIDAccess() {
        switch ssidAccess {
        case .notDetermined:
            location.request()
        case .denied:
            openPrivacySettings("Privacy_LocationServices")
        case .granted:
            networkMonitor.refresh()
        }
    }

    private func openPrivacySettings(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }

    // MARK: - 登录时启动

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemNote = nil
        } catch {
            loginItemNote = "设置失败：\(error.localizedDescription)"
        }
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginItemNote = "需要在“系统设置 › 通用 › 登录项”里允许 DuoBar。"
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
