import Foundation

/// 电源状态。
enum PowerState: Sendable, Equatable {
    /// 使用电池供电。
    case battery
    /// 已接通电源，正在充电。
    case charging
    /// 已接通电源，但没有在充电（已充满，或被优化充电暂停）。
    case pluggedIn
}

struct BatteryInfo: Sendable, Equatable {
    var hasBattery: Bool
    /// 0...100
    var percent: Int
    var power: PowerState
    var isCharged: Bool
    /// 预计还能用多久；系统还在计算时为 nil。
    var minutesToEmpty: Int?
    /// 预计多久充满；系统还在计算时为 nil。
    var minutesToFull: Int?
    var lowPowerMode: Bool

    static let placeholder = BatteryInfo(
        hasBattery: false, percent: 100, power: .pluggedIn, isCharged: true,
        minutesToEmpty: nil, minutesToFull: nil, lowPowerMode: false
    )

    var isLow: Bool { hasBattery && percent <= 20 }

    /// 电量变色：低电量模式黄色；接着电源绿色（可以关掉）；没接电源且不高于 20% 红色。
    func tint(chargingGreen: Bool) -> DuoTint? {
        guard hasBattery else { return nil }
        if lowPowerMode { return .yellow }
        if power != .battery { return chargingGreen ? .green : nil }
        return isLow ? .red : nil
    }
}

/// 当前主要的网络连接方式。
enum LinkKind: Sendable, Equatable {
    case wifi
    /// 通过 Wi-Fi 连到了个人热点（系统把这类网络标记为“昂贵”）。
    case hotspot
    case ethernet
    case other
    case none
}

struct NetworkInfo: Sendable, Equatable {
    var link: LinkKind
    var hasWiFiHardware: Bool
    var wifiPowered: Bool
    var wifiAssociated: Bool
    /// 没有定位权限时 macOS 不会返回 Wi-Fi 名称。
    var ssid: String?
    var rssi: Int?
    var noise: Int?
    var txRate: Double?
    var channel: Int?
    var band: String?

    static let placeholder = NetworkInfo(
        link: .none, hasWiFiHardware: false, wifiPowered: false, wifiAssociated: false,
        ssid: nil, rssi: nil, noise: nil, txRate: nil, channel: nil, band: nil
    )

    /// 底部圆点点亮的数量（0...4）。有线网络始终满格。
    var signalLevel: Int {
        if link == .ethernet { return 4 }
        guard wifiAssociated, let rssi else { return 0 }
        return Self.level(forRSSI: rssi)
    }

    static func level(forRSSI rssi: Int) -> Int {
        if rssi >= -55 { 4 } else if rssi >= -65 { 3 } else if rssi >= -75 { 2 } else { 1 }
    }
}

/// 网络状态对应的图形。
enum CenterGlyph: Sendable, Equatable {
    /// Wi-Fi 已打开；connected 为 false 时整体变暗。
    case wifi(connected: Bool)
    case wifiOff
    case hotspot
    case ethernet

    init(_ network: NetworkInfo) {
        switch network.link {
        case .ethernet: self = .ethernet
        case .hotspot: self = .hotspot
        case .wifi: self = .wifi(connected: true)
        case .other, .none:
            if network.hasWiFiHardware && !network.wifiPowered {
                self = .wifiOff
            } else {
                self = .wifi(connected: network.wifiAssociated)
            }
        }
    }
}
