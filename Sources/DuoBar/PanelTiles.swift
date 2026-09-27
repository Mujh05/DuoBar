import SwiftUI

/// 面板顶部的几个控制中心样式胶囊，以及打开面板时的拆分动画。面板和设置窗口里的预览共用这一份。
///
/// progress = 0 时所有胶囊叠在第一个的位置，三部分拼成完整的三合一图标；到 1 时胶囊滑开，
/// 外圈、中间和底部圆点各自落进一个胶囊的圆形图标里（见 DuoPartGlyph）。
/// macOS 26 起胶囊是玻璃，放在同一个容器里，滑开时像一滴水分成几滴。
struct PanelTiles: View {
    let model: AppModel
    /// 拆分进度：0 是合体，1 是拆开。
    var progress: CGFloat
    /// 展开的那一项；其他胶囊收起。
    var selected: PanelTab?
    /// 点胶囊时调用。nil 表示只用来展示（设置里的预览），胶囊不响应点击。
    var onSelect: ((PanelTab) -> Void)?
    /// 高度跟着拆分进度变：合起来时只有一个胶囊高，拆开时往下长出其他胶囊。
    /// 设置里的预览用；面板打开时窗口已经按拆开后的大小定好，不用。
    var shrinksWhenMerged = false

    /// 从上到下：外圈、中间、底部圆点。
    private static let slotOrder: [Slot] = [.ring, .center, .dots]
    private static let spacing: CGFloat = 8

    var body: some View {
        // 玻璃挨得比这更近就会连在一起；胶囊停下时隔 8 点，是分开的。
        TileGlassContainer(spacing: 6) {
            VStack(spacing: Self.spacing) {
                ForEach(Array(tabs.enumerated()), id: \.element) { index, item in
                    if selected == nil || selected == item {
                        SplitSlide(progress: progress, index: index,
                                   step: ModuleTile<EmptyView>.height + Self.spacing) { reveal, progress in
                            tile(item, reveal: reveal, progress: progress)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                }
            }
        }
        .frame(height: shrinksWhenMerged ? mergedHeight : nil, alignment: .top)
        .allowsHitTesting(onSelect != nil)
    }

    /// 第一个胶囊的高度，加上其他胶囊按进度滑出来的距离。
    private var mergedHeight: CGFloat {
        let step = ModuleTile<EmptyView>.height + Self.spacing
        return ModuleTile<EmptyView>.height + CGFloat(max(tabs.count - 1, 0)) * step * progress
    }

    /// 要显示的胶囊：图标上有的位置，网络不在图标上时再加一个 Wi-Fi。
    private var tabs: [PanelTab] {
        var result = Self.slotOrder.filter { model.layout[$0] != nil }.map(PanelTab.slot)
        if model.showWiFiControls, model.network.hasWiFiHardware, !model.layout.metricKinds.contains(.network) {
            result.append(.wifi)
        }
        return result
    }

    /// 胶囊上的文字、图标状态，以及点圆形图标能做的事。
    private struct TileInfo {
        var title: String
        var subtitle: String?
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
                       expanded: selected == item, reveal: reveal, iconAction: info.iconAction, iconHelp: info.iconHelp,
                       action: { onSelect?(item) }) {
                SymbolGlyph(name: model.network.wifiPowered ? "wifi" : "wifi.slash",
                            variable: model.network.wifiAssociated ? Double(max(model.network.signalLevel, 1)) / 4 : nil)
                    .opacity(reveal)
            }
        case let .slot(slot):
            if let content = model.layout[slot] {
                let info = info(for: content)
                ModuleTile(title: info.title, subtitle: info.subtitle, active: info.active, tint: info.tint,
                           expanded: selected == item, reveal: reveal, iconAction: info.iconAction, iconHelp: info.iconHelp,
                           action: { onSelect?(item) }) {
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
        return TileInfo(title: battery.hasBattery ? "电池" : "电源", subtitle: battery.summary(limit: model.chargeLimit, starting: model.chargeStarting),
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
        return TileInfo(title: "指示灯", subtitle: lit.isEmpty ? nil : lit.map(\.title).joined(separator: "、"),
                        active: !lit.isEmpty)
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
