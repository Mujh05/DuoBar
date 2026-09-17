import SwiftUI

/// 面板里的 Wi-Fi 开关和附近的网络，可以代替系统自带的 Wi-Fi 菜单。
struct WiFiSection: View {
    let model: AppModel
    /// 标题下面的一行说明，比如信号强度和频段。
    var summary: String?
    @State private var showOthers = false

    /// 网络列表右边留出的空隙，免得滚动条盖住信号图标。
    static let scrollerInset: CGFloat = 12

    private var currentSSID: String? {
        model.network.wifiAssociated ? model.network.ssid : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Wi-Fi")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if model.wifiScanning || model.wifiSwitching {
                    ProgressView()
                        .controlSize(.mini)
                }
                Spacer()
                Toggle("Wi-Fi", isOn: Binding(
                    get: { model.network.wifiPowered },
                    set: { model.setWiFiPower($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(model.wifiSwitching)
            }

            if let summary {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if model.network.wifiPowered {
                networkList
            }

            if let message = model.wifiMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Wi-Fi 设置…") { model.openWiFiSettings() }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var networkList: some View {
        let current = currentSSID
        let known = model.wifiNetworks.filter { $0.known && $0.ssid != current }
        let others = model.wifiNetworks.filter { !$0.known && $0.ssid != current }

        if let current {
            row(currentNetwork(current), connected: true)
        }
        if !known.isEmpty {
            subheader("已知网络")
            ForEach(known) { row($0, connected: false) }
        }
        if !others.isEmpty {
            DisclosureGroup(isExpanded: $showOthers) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(others) { row($0, connected: false) }
                    }
                }
                .frame(maxHeight: 132)
            } label: {
                subheader("其他网络（\(others.count)）")
            }
        }

        if model.wifiNetworks.isEmpty, model.wifiUnnamedCount > 0 || (model.network.wifiAssociated && current == nil) {
            // 扫描到了网络却读不到名称：macOS 需要定位权限才给名称。
            HStack(alignment: .firstTextBaseline) {
                Text("macOS 只把网络名称提供给有定位权限的 App，允许后才能显示和切换附近的网络。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(model.ssidAccess == .denied ? "去开启" : "允许") { model.requestSSIDAccess() }
                    .controlSize(.small)
            }
        } else if current == nil, model.wifiNetworks.isEmpty {
            Text(model.wifiScanning ? "正在搜索附近的网络…" : "附近没有找到网络")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    /// 当前网络：优先用扫描结果（知道是否加密），信号强度用实时读数。
    private func currentNetwork(_ ssid: String) -> WiFiNetwork {
        var network = model.wifiNetworks.first { $0.ssid == ssid }
            ?? WiFiNetwork(ssid: ssid, rssi: -60, secure: false, needsPassword: false, enterprise: false, known: true)
        if let rssi = model.network.rssi { network.rssi = rssi }
        return network
    }

    private func row(_ network: WiFiNetwork, connected: Bool) -> some View {
        NetworkRow(network: network, connected: connected,
                   joining: model.joiningSSID == network.ssid,
                   busy: model.joiningSSID != nil) {
            model.join(network)
        }
    }

    private func subheader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }
}

private struct NetworkRow: View {
    let network: WiFiNetwork
    let connected: Bool
    let joining: Bool
    let busy: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        // 当前网络不能点，但不应该显示成灰色的“禁用”样式，所以不做成按钮。
        if connected {
            content
                .help(helpText)
        } else {
            Button(action: action) {
                content
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(hovering && !busy ? Color.primary.opacity(0.08) : .clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .onHover { hovering = $0 }
            .help(helpText)
        }
    }

    private var content: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .opacity(connected ? 1 : 0)
                .frame(width: 12)
            Text(network.ssid)
                .font(.system(size: 12, weight: connected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if joining {
                ProgressView()
                    .controlSize(.mini)
            }
            if network.secure {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "wifi", variableValue: Double(network.level) / 4)
                .font(.system(size: 12))
        }
        .padding(.leading, 4)
        .padding(.trailing, WiFiSection.scrollerInset)
        .padding(.vertical, 3)
    }

    private var helpText: String {
        if connected { return "已连接" }
        if network.enterprise { return "企业网络需要在系统设置里用账号加入" }
        return network.known ? "切换到这个网络" : "加入这个网络"
    }
}
