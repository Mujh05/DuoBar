import SwiftUI

/// 面板里的 Wi-Fi 菜单，样子和系统菜单栏里的 Wi-Fi 菜单一样，可以代替它。
struct WiFiSection: View {
    let model: AppModel
    @State private var showOthers = false

    private var currentSSID: String? {
        model.network.wifiAssociated ? model.network.ssid : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuTitleRow(title: "Wi-Fi") {
                if model.wifiSwitching {
                    ProgressView()
                        .controlSize(.small)
                }
                Toggle("Wi-Fi", isOn: Binding(
                    get: { model.network.wifiPowered },
                    set: { model.setWiFiPower($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(model.wifiSwitching)
            }

            if model.network.wifiPowered {
                networkList
            }

            if let message = model.wifiMessage {
                MenuNote(text: message, color: .red)
            }

            MenuDivider()
            MenuItem(title: "Wi-Fi 设置…") { model.openWiFiSettings() }
        }
    }

    @ViewBuilder
    private var networkList: some View {
        let current = currentSSID
        let known = model.wifiNetworks.filter { $0.known && $0.ssid != current }
        let others = model.wifiNetworks.filter { !$0.known && $0.ssid != current }

        if needsLocationAccess {
            MenuRow(title: model.ssidAccess == .denied ? "去开启定位权限…" : "显示网络名称…",
                    subtitle: "macOS 只把网络名称提供给有定位权限的 App",
                    help: "DuoBar 只用它显示网络名称，不会读取你的位置。",
                    action: { model.requestSSIDAccess() }) {
                IconCircle(symbol: "location.fill", active: false)
            }
        } else if current != nil || !known.isEmpty {
            MenuSectionHeader(title: "已知网络")
            if let current {
                row(currentNetwork(current), connected: true)
            }
            ForEach(known) { row($0, connected: false) }
        } else if model.wifiNetworks.isEmpty {
            MenuNote(text: model.wifiScanning ? "正在搜索网络…" : "附近没有找到网络")
        }

        if !others.isEmpty {
            MenuRow(title: "其他网络", emphasized: false, action: {
                withAnimation(.snappy(duration: 0.25)) { showOthers.toggle() }
            }) {
                EmptyView()
            } trailing: {
                if model.wifiScanning {
                    ProgressView()
                        .controlSize(.mini)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showOthers ? 90 : 0))
            }
            if showOthers {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(others) { row($0, connected: false) }
                    }
                }
                .frame(maxHeight: 200)
                .transition(.opacity)
            }
        }
    }

    /// 扫描到了网络却读不到名称：macOS 需要定位权限才给名称。
    private var needsLocationAccess: Bool {
        model.wifiNetworks.isEmpty
            && (model.wifiUnnamedCount > 0 || (model.network.wifiAssociated && currentSSID == nil))
    }

    /// 当前网络：优先用扫描结果（知道是否加密），信号强度用实时读数。
    private func currentNetwork(_ ssid: String) -> WiFiNetwork {
        var network = model.wifiNetworks.first { $0.ssid == ssid }
            ?? WiFiNetwork(ssid: ssid, rssi: -60, secure: false, needsPassword: false, enterprise: false, known: true)
        if let rssi = model.network.rssi { network.rssi = rssi }
        return network
    }

    private func row(_ network: WiFiNetwork, connected: Bool) -> some View {
        let joining = model.joiningSSID == network.ssid
        let busy = model.joiningSSID != nil
        return MenuRow(
            title: network.ssid,
            subtitle: connected ? currentDetail : nil,
            help: helpText(network, connected: connected),
            action: connected || busy ? nil : { model.join(network) }
        ) {
            IconCircle(symbol: "wifi", variable: Double(max(network.level, 1)) / 4, active: connected)
        } trailing: {
            if joining {
                ProgressView()
                    .controlSize(.mini)
            }
            if network.secure {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 已连接网络下面的小字：信号和频段。
    private var currentDetail: String? {
        let network = model.network
        let parts = [network.signalText, network.band].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func helpText(_ network: WiFiNetwork, connected: Bool) -> String {
        if connected { return "已连接" }
        if network.enterprise { return "企业网络需要在系统设置里用账号加入" }
        return network.known ? "切换到这个网络" : "加入这个网络"
    }
}
