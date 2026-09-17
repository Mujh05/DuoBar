import AppKit
import SwiftUI

/// 着色用的系统颜色，会随深色/浅色外观自动变化。
enum DuoTint: String, CaseIterable, Sendable {
    case green, yellow, red, orange, blue, purple, teal

    var nsColor: NSColor {
        switch self {
        case .green: .systemGreen
        case .yellow: .systemYellow
        case .red: .systemRed
        case .orange: .systemOrange
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .teal: .systemTeal
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

/// 底部圆点切到“独立指示灯”后，每个点可以显示的开关状态。
enum IndicatorKind: String, CaseIterable, Identifiable, Sendable {
    case bluetooth, wifi, internet, vpn, hotspot, ethernet
    case headphones, microphone, muted
    case charging, pluggedIn, lowPower, lowBattery
    case externalDisplay, capsLock, memoryPressure, diskLow

    var id: Self { self }

    var title: String {
        switch self {
        case .bluetooth: "蓝牙"
        case .wifi: "Wi-Fi"
        case .internet: "已联网"
        case .vpn: "VPN"
        case .hotspot: "个人热点"
        case .ethernet: "有线网络"
        case .headphones: "蓝牙耳机"
        case .microphone: "麦克风使用中"
        case .muted: "静音"
        case .charging: "正在充电"
        case .pluggedIn: "接着电源"
        case .lowPower: "低电量模式"
        case .lowBattery: "电量低"
        case .externalDisplay: "外接显示器"
        case .capsLock: "大写锁定"
        case .memoryPressure: "内存紧张"
        case .diskLow: "磁盘快满"
        }
    }

    var summary: String {
        switch self {
        case .bluetooth: "蓝牙打开时亮。第一次使用时系统会询问蓝牙权限，DuoBar 只读取开关状态。"
        case .wifi: "Wi-Fi 打开时亮。"
        case .internet: "有可用的网络连接时亮。"
        case .vpn: "连着 VPN 时亮。"
        case .hotspot: "正在通过 iPhone 个人热点上网时亮。"
        case .ethernet: "主要连接是有线网络时亮。"
        case .headphones: "声音从蓝牙设备（比如 AirPods）播放时亮。"
        case .microphone: "有 App 正在使用麦克风时亮。"
        case .muted: "输出设备静音时亮。"
        case .charging: "正在充电时亮。"
        case .pluggedIn: "接着电源适配器时亮（包括已充满）。"
        case .lowPower: "打开低电量模式时亮。"
        case .lowBattery: "电量不高于 20% 且没接电源时亮。"
        case .externalDisplay: "连接了外接显示器时亮。"
        case .capsLock: "大写锁定打开时亮。"
        case .memoryPressure: "系统内存压力偏高或紧张时亮。"
        case .diskLow: "启动磁盘可用空间少于 10% 时亮。"
        }
    }

    /// nil 表示用自己画的图形（蓝牙标志）。
    var symbol: String? {
        switch self {
        case .bluetooth: nil
        case .wifi: "wifi"
        case .internet: "globe"
        case .vpn: "lock.shield.fill"
        case .hotspot: "personalhotspot"
        case .ethernet: "cable.connector"
        case .headphones: "airpods"
        case .microphone: "mic.fill"
        case .muted: "speaker.slash.fill"
        case .charging: "bolt.fill"
        case .pluggedIn: "powerplug.fill"
        case .lowPower: "leaf.fill"
        case .lowBattery: "battery.25percent"
        case .externalDisplay: "display.2"
        case .capsLock: "capslock.fill"
        case .memoryPressure: "memorychip.fill"
        case .diskLow: "internaldrive.fill"
        }
    }

    /// 打开“指示灯颜色”时，亮起的点用这个颜色；nil 表示跟菜单栏文字同色。
    var tint: DuoTint? {
        switch self {
        case .bluetooth, .wifi, .headphones: .blue
        case .internet, .hotspot, .charging: .green
        case .vpn: .purple
        case .ethernet: .teal
        case .microphone, .memoryPressure: .orange
        case .muted, .lowBattery, .diskLow: .red
        case .lowPower: .yellow
        case .pluggedIn, .externalDisplay, .capsLock: nil
        }
    }

    func stateText(_ on: Bool?) -> String {
        guard let on else { return "未知" }
        switch self {
        case .bluetooth, .wifi: return on ? "已打开" : "已关闭"
        case .internet, .vpn, .ethernet, .headphones, .externalDisplay: return on ? "已连接" : "未连接"
        case .hotspot, .microphone: return on ? "正在使用" : "未使用"
        case .muted, .lowPower, .capsLock: return on ? "已开启" : "未开启"
        case .charging: return on ? "是" : "否"
        case .pluggedIn: return on ? "已接通" : "未接通"
        case .lowBattery, .memoryPressure, .diskLow: return on ? "是" : "正常"
        }
    }

    static let defaultSet: [IndicatorKind?] = [.wifi, .bluetooth, .vpn, .microphone]
}

enum Glyphs {
    /// 蓝牙标志，SF Symbols 里没有，自己画。rect 里按高度居中。
    static func bluetoothRune(in rect: CGRect) -> Path {
        let h = rect.height, cx = rect.midX, cy = rect.midY
        let w = h * 0.26
        var path = Path()
        path.move(to: CGPoint(x: cx - w, y: cy - h * 0.25))
        path.addLine(to: CGPoint(x: cx + w, y: cy + h * 0.25))
        path.addLine(to: CGPoint(x: cx, y: cy + h * 0.5))
        path.addLine(to: CGPoint(x: cx, y: cy - h * 0.5))
        path.addLine(to: CGPoint(x: cx + w, y: cy - h * 0.25))
        path.addLine(to: CGPoint(x: cx - w, y: cy + h * 0.25))
        return path
    }

    /// 从已画的圆点里镂空出指示灯的图形。
    static func indicatorKnockout(_ kind: IndicatorKind, in rect: CGRect) -> DuoMark {
        if let symbol = kind.symbol {
            return .knockoutSymbol(symbol, rect: rect)
        }
        let inner = rect.insetBy(dx: 0, dy: rect.height * 0.04)
        return .knockout(bluetoothRune(in: inner), width: rect.height * 0.13)
    }
}

/// 设置和面板里用的指示灯小图标。
struct IndicatorIcon: View {
    let kind: IndicatorKind
    /// 蓝牙标志的高度；SF Symbols 跟随外面设置的字体大小。
    var size: CGFloat = 14

    var body: some View {
        if let symbol = kind.symbol {
            Image(systemName: symbol)
        } else {
            BluetoothRuneShape()
                .stroke(style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.7, height: size)
        }
    }
}

private struct BluetoothRuneShape: Shape {
    func path(in rect: CGRect) -> Path {
        Glyphs.bluetoothRune(in: rect)
    }
}
