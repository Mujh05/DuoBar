import Foundation

// 把各个数据源的原始数值整理成 MetricReading。
extension MetricReading {
    static func battery(_ info: BatteryInfo) -> MetricReading {
        var rows: [DetailRow] = []
        if info.hasBattery {
            rows.append(DetailRow(label: "电量", value: "\(info.percent)%"))
            rows.append(DetailRow(label: "状态", value: info.stateText))
            if let time = info.timeText {
                rows.append(DetailRow(label: "时间", value: time))
            }
            if info.lowPowerMode {
                rows.append(DetailRow(label: "低电量模式", value: "已开启"))
            }
        } else {
            rows.append(DetailRow(label: "电源", value: "电源适配器（无内置电池）"))
        }
        return MetricReading(
            level: info.hasBattery ? Double(info.percent) / 100 : 1,
            active: true,
            value: info.hasBattery ? "\(info.percent)%" : "电源",
            compact: info.hasBattery ? "\(info.percent)" : "AC",
            rows: rows,
            power: info.hasBattery ? info.power : nil
        )
    }

    /// Wi-Fi 名称那一行由面板单独处理，因为可能要显示授权按钮。
    static func network(_ info: NetworkInfo) -> MetricReading {
        var rows = [DetailRow(label: "连接", value: info.linkText)]
        if let signal = info.signalText {
            rows.append(DetailRow(label: "信号", value: signal))
        }
        if let detail = info.detailText {
            rows.append(DetailRow(label: "频段", value: detail))
        }
        return MetricReading(
            level: Double(info.signalLevel) / 4,
            active: info.signalLevel > 0,
            value: info.headline,
            compact: "",
            rows: rows,
            glyph: CenterGlyph(info),
            dots: info.signalLevel
        )
    }

    static func cpu(_ usage: Double) -> MetricReading {
        percentage(usage, rows: [
            DetailRow(label: "占用", value: percentText(usage)),
            DetailRow(label: "核心", value: "\(ProcessInfo.processInfo.activeProcessorCount) 个"),
        ])
    }

    static func gpu(_ usage: Double) -> MetricReading {
        percentage(usage, rows: [DetailRow(label: "占用", value: percentText(usage))])
    }

    static func memory(_ sample: MemorySample) -> MetricReading {
        let fraction = sample.total > 0 ? Double(sample.used) / Double(sample.total) : 0
        let pressure = switch sample.pressure {
        case 4: "紧张"
        case 2: "偏高"
        default: "正常"
        }
        return percentage(fraction, rows: [
            DetailRow(label: "已用", value: "\(memoryText(sample.used)) / \(memoryText(sample.total))"),
            DetailRow(label: "内存压力", value: pressure),
        ])
    }

    static func disk(_ sample: DiskSample) -> MetricReading {
        let used = max(sample.total - sample.available, 0)
        let fraction = sample.total > 0 ? Double(used) / Double(sample.total) : 0
        return percentage(fraction, rows: [
            DetailRow(label: "已用", value: "\(fileText(used)) / \(fileText(sample.total))"),
            DetailRow(label: "可用", value: fileText(sample.available)),
        ])
    }

    static func throughput(_ sample: ThroughputSample) -> MetricReading {
        let total = sample.upload + sample.download
        // 1 KB/s 记为 0，100 MB/s 记为满。
        let level = min(max(log10(max(total, 1) / 1_000) / 5, 0), 1)
        return MetricReading(
            level: level,
            active: true,
            value: speedText(total),
            compact: compactSpeed(total),
            rows: [
                DetailRow(label: "上传", value: speedText(sample.upload)),
                DetailRow(label: "下载", value: speedText(sample.download)),
            ]
        )
    }

    static func volume(_ sample: AudioSample) -> MetricReading {
        let percent = Int((sample.level * 100).rounded())
        var rows = [
            DetailRow(label: "音量", value: "\(percent)%"),
            DetailRow(label: "状态", value: sample.muted ? "已静音" : "正常"),
        ]
        if let name = sample.deviceName {
            rows.append(DetailRow(label: "输出设备", value: name))
        }
        return MetricReading(
            level: sample.level,
            active: !sample.muted,
            value: sample.muted ? "静音" : "\(percent)%",
            compact: "\(percent)",
            rows: rows,
            symbol: sample.muted ? "speaker.slash.fill" : "speaker.wave.3.fill"
        )
    }

    static func accessories(_ devices: [AccessoryBattery]) -> MetricReading {
        guard let lowest = devices.min(by: { $0.percent < $1.percent }) else {
            return .unavailable("没有连接能读到电量的外设", value: "无")
        }
        return MetricReading(
            level: Double(lowest.percent) / 100,
            active: true,
            value: "\(lowest.percent)%",
            compact: "\(lowest.percent)",
            rows: devices.map { DetailRow(label: $0.name, value: "\($0.percent)%") }
        )
    }

    // MARK: - 格式化

    private static func percentage(_ fraction: Double, rows: [DetailRow]) -> MetricReading {
        let clamped = min(max(fraction, 0), 1)
        let percent = Int((clamped * 100).rounded())
        return MetricReading(level: clamped, active: true, value: "\(percent)%", compact: "\(percent)", rows: rows)
    }

    private static func percentText(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    private static func memoryText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }

    private static func fileText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 和“活动监视器”一样按 1000 进位。
    static func speedText(_ bytesPerSecond: Double) -> String {
        let value = max(bytesPerSecond, 0)
        if value < 1_000 { return "\(Int(value)) B/s" }
        if value < 999_500 { return "\(Int((value / 1_000).rounded())) KB/s" }
        if value < 9_950_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
        if value < 999_500_000 { return "\(Int((value / 1_000_000).rounded())) MB/s" }
        return String(format: "%.1f GB/s", value / 1_000_000_000)
    }

    /// 最多 4 个字符，放得进圆环中间。
    static func compactSpeed(_ bytesPerSecond: Double) -> String {
        let value = max(bytesPerSecond, 0)
        if value < 1_000 { return "\(Int(value))B" }
        if value < 999_500 { return "\(Int((value / 1_000).rounded()))K" }
        if value < 9_950_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value < 999_500_000 { return "\(Int((value / 1_000_000).rounded()))M" }
        return String(format: "%.1fG", value / 1_000_000_000)
    }
}
