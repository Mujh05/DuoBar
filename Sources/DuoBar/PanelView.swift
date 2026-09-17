import SwiftUI

/// 点击菜单栏图标后弹出的面板。打开时三合一图标会拆成三个独立图标，和 iPhone Duo 打开控制中心时一样。
struct PanelView: View {
    let model: AppModel
    /// 仅用于渲染预览：固定为拆开或合体，不播放动画。
    var previewSplit: Bool?
    @State private var animatedSplit = false

    private var split: Bool { previewSplit ?? animatedSplit }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 14)
            ForEach(model.detailSections) { section in
                Divider()
                switch section {
                case let .metric(kind):
                    self.section(kind.title) { rows(for: kind) }
                case .indicators:
                    self.section("指示灯") { indicatorRows }
                }
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
        .onChange(of: model.panelVisible, initial: true) { _, visible in
            guard previewSplit == nil else { return }
            if visible {
                withAnimation(.spring(duration: 0.75, bounce: 0.22).delay(0.12)) { animatedSplit = true }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { animatedSplit = false }
            }
        }
    }

    // MARK: - 顶部动画

    private var header: some View {
        VStack(spacing: 10) {
            SplitGlyphView(progress: split ? 1 : 0, state: model.iconState)
                .frame(height: 76)
            // 拆开后的顺序：底部圆点在左，中间在中，外圈在右。
            HStack(spacing: 0) {
                caption(.dots)
                caption(.center)
                caption(.ring)
            }
            .opacity(split ? 1 : 0)
            .animation(.easeOut(duration: 0.3).delay(split ? 0.35 : 0), value: split)
        }
    }

    private func caption(_ slot: Slot) -> some View {
        let text: (title: String, subtitle: String)? = switch model.layout[slot] {
        case let .metric(kind): (model.reading(kind).value, kind.shortTitle)
        case .indicators: (litSummary, "指示灯亮起")
        case nil: nil
        }
        return VStack(spacing: 2) {
            if let text {
                Text(text.title)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text(text.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    private var litSummary: String {
        let kinds = model.layout.indicators.compactMap { $0 }
        let lit = kinds.filter { model.indicatorStates[$0] == true }.count
        return "\(lit)/\(kinds.count)"
    }

    // MARK: - 各状态的详情

    @ViewBuilder
    private func rows(for kind: MetricKind) -> some View {
        let reading = model.reading(kind)
        ForEach(Array(reading.rows.enumerated()), id: \.offset) { index, item in
            row(item.label, item.value)
            // 网络的第一行是“连接”，Wi-Fi 名称紧跟其后。
            if kind == .network, index == 0, model.network.wifiAssociated {
                ssidRow
            }
        }
    }

    private var ssidRow: some View {
        HStack {
            label("Wi-Fi 名称")
            Spacer(minLength: 12)
            if let ssid = model.network.ssid {
                Text(ssid).font(.system(size: 12))
            } else {
                Button(model.ssidAccess == .denied ? "去开启定位权限" : "显示名称") {
                    model.requestSSIDAccess()
                }
                .controlSize(.small)
                .help("macOS 只把 Wi-Fi 名称提供给有定位权限的 App，DuoBar 不会读取你的位置。")
            }
        }
    }

    private var indicatorRows: some View {
        ForEach(Array(model.layout.indicators.enumerated()), id: \.offset) { _, kind in
            if let kind {
                HStack(spacing: 8) {
                    StatusDot(on: model.indicatorStates[kind] == true,
                              tint: model.indicatorColors ? kind.tint : nil)
                    label(kind.title)
                    Spacer(minLength: 12)
                    if kind == .bluetooth, model.bluetoothAccess == .denied {
                        Button("去开启蓝牙权限") { model.requestBluetoothAccess() }
                            .controlSize(.small)
                    } else {
                        Text(model.indicatorText(kind))
                            .font(.system(size: 12))
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("自定义图标…") { model.openSettings() }
            Spacer()
            Button("退出 DuoBar") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
        .padding(.top, 12)
    }

    // MARK: - 小部件

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.vertical, 12)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            label(title)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

/// 指示灯当前是否亮起的小圆点。
struct StatusDot: View {
    let on: Bool
    let tint: DuoTint?

    var body: some View {
        Circle()
            .fill(on ? (tint?.color ?? Color.primary) : Color.secondary.opacity(0.3))
            .frame(width: 7, height: 7)
    }
}
