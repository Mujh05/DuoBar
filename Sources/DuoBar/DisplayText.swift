import Foundation

extension BatteryInfo {
    var stateText: String {
        guard hasBattery else { return "使用电源适配器" }
        switch power {
        case .battery: return "使用电池"
        case .charging: return "正在充电"
        case .pluggedIn: return isCharged || percent >= 100 ? "已充满" : "已接电源，暂停充电"
        }
    }

    var timeText: String? {
        guard hasBattery else { return nil }
        switch power {
        case .battery: return minutesToEmpty.map { "约可使用 \(Self.duration($0))" } ?? "正在估算…"
        case .charging: return minutesToFull.map { "约 \(Self.duration($0))后充满" } ?? "正在估算…"
        case .pluggedIn: return nil
        }
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) 分钟" }
        if rest == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(rest) 分钟"
    }
}

extension NetworkInfo {
    var linkText: String {
        switch link {
        case .wifi: return "Wi-Fi"
        case .hotspot: return "个人热点"
        case .ethernet: return "以太网"
        case .other: return "其他网络"
        case .none:
            guard hasWiFiHardware else { return "未连接" }
            if !wifiPowered { return "Wi-Fi 已关闭" }
            return wifiAssociated ? "Wi-Fi（无网络）" : "未连接"
        }
    }

    /// 面板中间那一栏的主标题。
    var headline: String {
        switch link {
        case .ethernet: return "以太网"
        case .other: return "其他网络"
        case .wifi, .hotspot, .none:
            if wifiAssociated { return ssid ?? "Wi-Fi" }
            return hasWiFiHardware && !wifiPowered ? "已关闭" : "未连接"
        }
    }

    var signalWord: String {
        if link == .ethernet { return "有线" }
        return ["无", "较弱", "一般", "良好", "极佳"][signalLevel]
    }

    var signalText: String? {
        guard wifiAssociated, let rssi else { return nil }
        return "\(signalWord) · \(rssi) dBm"
    }

    var detailText: String? {
        guard wifiAssociated else { return nil }
        var parts: [String] = []
        if let band { parts.append(band) }
        if let channel { parts.append("信道 \(channel)") }
        if let txRate, txRate > 0 { parts.append("\(Int(txRate)) Mbps") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
