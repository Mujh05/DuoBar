import CoreWLAN
import Foundation
import Network

/// 汇总网络状态：连接方式来自 NWPathMonitor，Wi-Fi 细节来自 CoreWLAN。
@MainActor
final class NetworkMonitor {
    private(set) var info = NetworkInfo.placeholder
    var onChange: ((NetworkInfo) -> Void)?

    /// 面板打开时加快刷新，让信号强度看起来是“活的”。
    var fastPolling = false {
        didSet { if fastPolling != oldValue { restartPolling() } }
    }

    private let pathMonitor = NWPathMonitor()
    private var path = PathSummary(satisfied: false, primary: nil, expensive: false)
    private var pollTask: Task<Void, Never>?

    private struct PathSummary: Sendable {
        var satisfied: Bool
        var primary: NWInterface.InterfaceType?
        var expensive: Bool

        init(satisfied: Bool, primary: NWInterface.InterfaceType?, expensive: Bool) {
            self.satisfied = satisfied
            self.primary = primary
            self.expensive = expensive
        }

        init(_ path: NWPath) {
            satisfied = path.status == .satisfied
            // availableInterfaces 按系统的服务顺序排列，第一个就是当前主连接。
            primary = path.availableInterfaces.first?.type
            expensive = path.isExpensive
        }
    }

    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] newPath in
            let summary = PathSummary(newPath)
            MainActor.assumeIsolated {
                self?.path = summary
                self?.refresh()
            }
        }
        pathMonitor.start(queue: .main)
        restartPolling()
    }

    private func restartPolling() {
        pollTask?.cancel()
        let interval: Duration = fastPolling ? .seconds(2) : .seconds(8)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: interval, tolerance: interval / 4)
            }
        }
    }

    func refresh() {
        let iface = CWWiFiClient.shared().interface()
        var new = NetworkInfo.placeholder
        new.hasWiFiHardware = iface != nil

        if let iface {
            new.wifiPowered = iface.powerOn()
            let rssi = iface.rssiValue()
            // 没连上任何 Wi-Fi 时 RSSI 为 0。
            new.wifiAssociated = new.wifiPowered && rssi != 0
            if new.wifiAssociated {
                new.ssid = iface.ssid()
                new.rssi = rssi
                new.noise = iface.noiseMeasurement()
                new.txRate = iface.transmitRate()
                if let channel = iface.wlanChannel() {
                    new.channel = channel.channelNumber
                    new.band = switch channel.channelBand {
                    case .band2GHz: "2.4 GHz"
                    case .band5GHz: "5 GHz"
                    case .band6GHz: "6 GHz"
                    default: nil
                    }
                }
            }
        }

        new.link = if !path.satisfied {
            .none
        } else {
            switch path.primary {
            case .wiredEthernet: .ethernet
            case .wifi: path.expensive ? .hotspot : .wifi
            case nil: .none
            default: .other
            }
        }

        guard new != info else { return }
        info = new
        onChange?(new)
    }
}
