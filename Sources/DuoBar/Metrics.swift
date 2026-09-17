import Foundation

/// 图标里可以显示的状态。
enum MetricKind: String, CaseIterable, Identifiable, Sendable {
    case battery, network, cpu, gpu, memory, disk, throughput, volume, accessory

    var id: Self { self }

    var title: String {
        switch self {
        case .battery: "电量"
        case .network: "网络"
        case .cpu: "CPU 占用"
        case .gpu: "GPU 占用"
        case .memory: "内存占用"
        case .disk: "磁盘空间"
        case .throughput: "网速"
        case .volume: "音量"
        case .accessory: "蓝牙外设电量"
        }
    }

    /// 面板里图标下方的小字。
    var shortTitle: String {
        switch self {
        case .battery: "电量"
        case .network: "网络"
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "内存"
        case .disk: "磁盘"
        case .throughput: "网速"
        case .volume: "音量"
        case .accessory: "外设"
        }
    }

    var symbol: String {
        switch self {
        case .battery: "battery.75percent"
        case .network: "wifi"
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .throughput: "arrow.up.arrow.down"
        case .volume: "speaker.wave.2.fill"
        case .accessory: "keyboard"
        }
    }

    var summary: String {
        switch self {
        case .battery: "内置电池的剩余电量。放在外圈时，充电显示闪电，接着电源但没在充电显示插头。"
        case .network: "当前连接方式（Wi-Fi、以太网、个人热点）。数值是 Wi-Fi 信号强度，有线网络算满格。"
        case .cpu: "所有核心的平均占用率，每 2 秒更新。"
        case .gpu: "图形处理器的占用率，每 2 秒更新。"
        case .memory: "已用内存（App 内存 + 联动内存 + 被压缩的内存）占总内存的比例。"
        case .disk: "启动磁盘已用空间的比例，每分钟更新。"
        case .throughput: "所有网卡上传加下载的总速度，从 1 KB/s 到 100 MB/s 按数量级显示。"
        case .volume: "当前输出设备的音量，静音时变暗。"
        case .accessory: "妙控键盘、鼠标、触控板等蓝牙外设里最低的电量。读不到 AirPods 的电量。"
        }
    }
}

/// 图标上的三个位置。
enum Slot: Int, CaseIterable, Identifiable, Sendable {
    case ring, center, dots

    var id: Self { self }

    var title: String {
        switch self {
        case .ring: "外圈圆环"
        case .center: "中间"
        case .dots: "底部圆点"
        }
    }

    var hint: String {
        switch self {
        case .ring: "按比例填满圆环"
        case .center: "显示图标或数字"
        case .dots: "按档位点亮，或每个点单独显示一项"
        }
    }
}

/// 一个位置上放的内容。
enum SlotContent: Hashable, Sendable {
    case metric(MetricKind)
    /// 只能放在底部圆点：4 个点各自显示一个开关状态。
    case indicators

    var metric: MetricKind? {
        if case let .metric(kind) = self { kind } else { nil }
    }

    var title: String {
        switch self {
        case let .metric(kind): kind.title
        case .indicators: "独立指示灯"
        }
    }

    var symbol: String {
        switch self {
        case let .metric(kind): kind.symbol
        case .indicators: "circle.grid.2x2"
        }
    }
}

/// 三个位置各放什么，以及 4 个指示灯各显示什么。
struct IconLayout: Equatable, Sendable {
    private var slots: [SlotContent?]
    /// 从左到右 4 个圆点各自显示的状态，只在底部圆点为“独立指示灯”时生效。
    private(set) var indicators: [IndicatorKind?]

    static let dotCount = 4

    init(ring: SlotContent?, center: SlotContent?, dots: SlotContent?,
         indicators: [IndicatorKind?] = IndicatorKind.defaultSet) {
        slots = [ring, center, dots]
        self.indicators = Self.normalized(indicators)
    }

    static let standard = IconLayout(ring: .metric(.battery), center: .metric(.network), dots: .metric(.cpu))

    subscript(slot: Slot) -> SlotContent? { slots[slot.rawValue] }

    func metric(at slot: Slot) -> MetricKind? { self[slot]?.metric }

    /// “独立指示灯”只能放在底部；至少要留一个位置。返回是否改成功。
    @discardableResult
    mutating func set(_ content: SlotContent?, at slot: Slot) -> Bool {
        if content == .indicators && slot != .dots { return false }
        var copy = slots
        copy[slot.rawValue] = content
        guard copy.contains(where: { $0 != nil }) else { return false }
        slots = copy
        return true
    }

    @discardableResult
    mutating func swapAt(_ a: Slot, _ b: Slot) -> Bool {
        guard a != b else { return false }
        if (self[a] == .indicators && b != .dots) || (self[b] == .indicators && a != .dots) { return false }
        slots.swapAt(a.rawValue, b.rawValue)
        return true
    }

    mutating func setIndicator(_ kind: IndicatorKind?, at index: Int) {
        guard indicators.indices.contains(index) else { return }
        indicators[index] = kind
    }

    mutating func swapIndicators(_ a: Int, _ b: Int) {
        guard indicators.indices.contains(a), indicators.indices.contains(b) else { return }
        indicators.swapAt(a, b)
    }

    func canClear(_ slot: Slot) -> Bool {
        Slot.allCases.contains { $0 != slot && self[$0] != nil }
    }

    var usesIndicators: Bool { self[.dots] == .indicators }
    var metricKinds: Set<MetricKind> { Set(slots.compactMap { $0?.metric }) }
    var activeIndicators: Set<IndicatorKind> {
        usesIndicators ? Set(indicators.compactMap { $0 }) : []
    }

    func slots(showing kind: MetricKind) -> [Slot] {
        Slot.allCases.filter { metric(at: $0) == kind }
    }

    func dots(showing kind: IndicatorKind) -> [Int] {
        usesIndicators ? indicators.indices.filter { indicators[$0] == kind } : []
    }

    // 存成 "battery,network,indicators;wifi,bluetooth,none,microphone"，空位写 "none"。

    var storageValue: String {
        let slotNames = slots.map { content -> String in
            switch content {
            case nil: "none"
            case .indicators: "indicators"
            case let .metric(kind): kind.rawValue
            }
        }
        let dotNames = indicators.map { $0?.rawValue ?? "none" }
        return slotNames.joined(separator: ",") + ";" + dotNames.joined(separator: ",")
    }

    init?(storageValue: String) {
        let sections = storageValue.split(separator: ";", omittingEmptySubsequences: false)
        let names = sections[0].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard names.count == Slot.allCases.count else { return nil }
        slots = names.enumerated().map { index, name in
            if name == "indicators" {
                return index == Slot.dots.rawValue ? .indicators : nil
            }
            return MetricKind(rawValue: name).map(SlotContent.metric)
        }
        if sections.count > 1 {
            let dotNames = sections[1].split(separator: ",", omittingEmptySubsequences: false)
            indicators = Self.normalized(dotNames.map { IndicatorKind(rawValue: String($0)) })
        } else {
            indicators = IndicatorKind.defaultSet
        }
        if slots.allSatisfy({ $0 == nil }) { return nil }
    }

    private static func normalized(_ list: [IndicatorKind?]) -> [IndicatorKind?] {
        Array((list + Array(repeating: nil, count: dotCount)).prefix(dotCount))
    }
}

struct DetailRow: Sendable, Equatable, Hashable {
    var label: String
    var value: String
}

/// 某个状态的一次读数。
struct MetricReading: Sendable, Equatable {
    /// 0...1，决定圆环填充和圆点档位。
    var level: Double
    /// false 时整体变暗：断网、静音、没有外设……
    var active: Bool
    /// 面板里显示的数值，例如“73%”“1.2 MB/s”。
    var value: String
    /// 放在圆环中间时显示的短文字，例如“73”“1.2M”。
    var compact: String
    var rows: [DetailRow]
    /// 只有电量有：顶部显示闪电或插头。
    var power: PowerState?
    /// 只有网络有：中间画网络图形而不是文字。
    var glyph: CenterGlyph?
    /// 只有音量有：中间画这个符号而不是文字。
    var symbol: String?
    /// 直接指定点亮几个圆点（网络信号）；nil 时按 level 换算。
    var dots: Int?

    static func unavailable(_ note: String = "暂无数据", value: String = "—") -> MetricReading {
        MetricReading(level: 0, active: false, value: value, compact: "–",
                      rows: [DetailRow(label: "状态", value: note)])
    }

    var litDots: Int {
        if let dots { return min(max(dots, 0), IconLayout.dotCount) }
        guard active else { return 0 }
        return [0.05, 0.3, 0.55, 0.8].filter { level >= $0 }.count
    }
}

/// 图标上一个位置真正需要画的内容。只保留影响外观的字段，避免无谓的重画。
struct IconPart: Sendable, Equatable {
    var kind: MetricKind
    var level: Double
    var active: Bool
    var compact: String
    var power: PowerState?
    var glyph: CenterGlyph?
    var symbol: String?
    var dots: Int
    /// 着色（目前只有电量会变色）。
    var tint: DuoTint?

    init(kind: MetricKind, reading: MetricReading, tint: DuoTint? = nil) {
        self.kind = kind
        level = (min(max(reading.level, 0), 1) * 100).rounded() / 100
        active = reading.active
        compact = reading.compact
        power = reading.power
        glyph = reading.glyph
        symbol = reading.symbol
        dots = reading.litDots
        self.tint = tint
    }
}

/// 一个圆点。
struct DotLight: Sendable, Equatable {
    var on: Bool
    /// 亮起时的颜色；nil 表示跟菜单栏文字同色。
    var tint: DuoTint?
    /// 独立指示灯模式下对应的状态。
    var indicator: IndicatorKind?
}

/// 底部 4 个圆点。
struct DotsPart: Sendable, Equatable {
    /// 从左到右；nil 表示这个位置空着，不画。
    var lights: [DotLight?]
    /// 显示某个状态的档位时为该状态；独立指示灯模式为 nil。
    var metric: MetricKind?

    var isIndicators: Bool { metric == nil }

    /// 把一个状态换算成档位。
    static func meter(_ part: IconPart) -> DotsPart {
        DotsPart(
            lights: (0 ..< IconLayout.dotCount).map { DotLight(on: $0 < part.dots, tint: part.tint) },
            metric: part.kind
        )
    }

    static func indicators(_ kinds: [IndicatorKind?], states: [IndicatorKind: Bool], colorful: Bool) -> DotsPart {
        DotsPart(
            lights: kinds.map { kind in
                kind.map { DotLight(on: states[$0] ?? false, tint: colorful ? $0.tint : nil, indicator: $0) }
            },
            metric: nil
        )
    }
}

/// 画一次图标所需的全部状态。
struct IconState: Sendable, Equatable {
    var ring: IconPart?
    var center: IconPart?
    var dots: DotsPart?

    /// 有颜色时菜单栏不能用模板图像。
    var hasTint: Bool {
        ring?.tint != nil || center?.tint != nil
            || (dots?.lights.contains { $0?.on == true && $0?.tint != nil } ?? false)
    }
}
