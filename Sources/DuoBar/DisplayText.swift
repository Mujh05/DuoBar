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

    /// 面板里电池那一格的小字，和系统电池菜单的标题一样，比如“84%，正在充电”。
    /// - Parameter starting: 刚点了“立即充满电”，系统还没真正开始充电。
    func summary(limit: ChargeLimitState?, starting: Bool = false) -> String {
        guard hasBattery else { return "电源适配器" }
        switch power {
        case .battery: return "\(percent)%"
        case .charging: return "\(percent)%，正在充电"
        case .pluggedIn:
            if isCharged || percent >= 100 { return "\(percent)%，已充满电" }
            if starting { return "\(percent)%，即将开始充电" }
            return limit?.source != nil ? "\(percent)%，暂停充电" : "\(percent)%，已连接电源"
        }
    }

    var powerSourceText: String {
        power == .battery ? "电源：电池" : "电源：电源适配器"
    }

    /// 电池菜单标题下面的说明，说法和系统电池菜单一致。
    /// - Parameters:
    ///   - starting: 刚点了“立即充满电”，系统还没真正开始充电。
    ///   - pausedLimit: 被“立即充满电”暂停了的手动上限。
    func statusLines(limit: ChargeLimitState?, starting: Bool = false,
                     pausedLimit: PausedChargeLimit? = nil) -> [String] {
        guard hasBattery else { return [] }
        var lines: [String] = []
        if starting, power == .pluggedIn, !isCharged, percent < 100 {
            lines.append("即将开始充电…")
            lines.append("系统通常需要一两分钟才开始充电")
            if let pausedLimit { lines.append(Self.pausedText(pausedLimit)) }
            return lines
        }
        switch power {
        case .battery:
            lines.append(minutesToEmpty.map { "约可使用 \(Self.duration($0))" } ?? "正在估算剩余时间…")
            if isLow { lines.append("尽快插入电源充电") }
        case .charging:
            if let limit, let source = limit.source, percent < limit.limit {
                lines.append(source == .manual ? "正在充电至 \(limit.limit)% 上限" : "电量达到 \(limit.limit)% 时将停止充电")
            } else if let minutesToFull {
                lines.append("完全充满电还需 \(Self.duration(minutesToFull))")
            }
        case .pluggedIn:
            if isCharged || percent >= 100 {
                lines.append("已充满电")
            } else if let limit, let source = limit.source {
                if source == .manual {
                    lines.append("已充电至 \(limit.limit)% 上限")
                } else {
                    lines.append("暂停充电")
                    if let deadline = limit.deadline { lines.append("将在\(Self.clockText(deadline))完成充电") }
                }
            } else {
                lines.append("电池没有在充电")
            }
        }
        if let pausedLimit, power != .battery, !isCharged { lines.append(Self.pausedText(pausedLimit)) }
        if slowCharger, power != .battery { lines.append("慢充") }
        if serviceRecommended { lines.append("建议维修") }
        return lines
    }

    /// “80% 上限已暂停，明天 06:00 恢复”
    private static func pausedText(_ paused: PausedChargeLimit) -> String {
        let time = paused.until.formatted(date: .omitted, time: .shortened)
        let day = Calendar.current.isDateInTomorrow(paused.until) ? "明天 " : ""
        return "\(paused.limit)% 上限已暂停，\(day)\(time) 自动恢复"
    }

    /// 能耗模式：自动、低电量或高电量。
    var energyModeText: String {
        if highPowerMode { return "高电量" }
        return lowPowerMode ? "低电量" : "自动"
    }

    /// “18:30”，不是今天时加上“明天”或日期。
    private static func clockText(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return " \(time) " }
        if calendar.isDateInTomorrow(date) { return "明天 \(time) " }
        return " \(date.formatted(.dateTime.month().day())) \(time) "
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
