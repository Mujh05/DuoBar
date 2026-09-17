import CoreWLAN
import Foundation

/// 附近的一个 Wi-Fi 网络（同名的多个接入点只保留信号最强的一个）。
struct WiFiNetwork: Identifiable, Sendable, Equatable {
    var ssid: String
    var rssi: Int
    /// 有密码或其他加密方式，显示小锁。
    var secure: Bool
    /// 加入时需要输入密码（不是开放网络或 OWE 增强开放网络）。
    var needsPassword: Bool
    /// 企业网络（802.1X），要在系统设置里用账号加入。
    var enterprise: Bool
    /// 系统里保存过的网络。
    var known: Bool

    var id: String { ssid }
    var level: Int { NetworkInfo.level(forRSSI: rssi) }
}

enum WiFiControlError: LocalizedError {
    case noInterface
    case notFound

    var errorDescription: String? {
        switch self {
        case .noInterface: "这台 Mac 没有 Wi-Fi"
        case .notFound: "附近找不到这个网络"
        }
    }
}

struct WiFiScan: Sendable {
    var networks: [WiFiNetwork]
    /// 扫描到了但读不到名称的网络数量（没有定位权限时 macOS 会隐藏名称）。
    var unnamed: Int
}

/// Wi-Fi 开关、扫描和加入网络。CoreWLAN 的这些调用会阻塞几秒，全部放到后台线程。
enum WiFiControl {
    static func scan() async throws -> WiFiScan {
        try await Task.detached(priority: .userInitiated) {
            guard let iface = CWWiFiClient.shared().interface() else { throw WiFiControlError.noInterface }
            let profiles = iface.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
            let known = Set(profiles.compactMap(\.ssid))

            var strongest: [String: WiFiNetwork] = [:]
            var unnamed = 0
            for network in try iface.scanForNetworks(withName: nil, includeHidden: false) {
                guard let ssid = network.ssid, !ssid.isEmpty else {
                    unnamed += 1
                    continue
                }
                if let existing = strongest[ssid], existing.rssi >= network.rssiValue { continue }
                strongest[ssid] = describe(network, ssid: ssid, known: known.contains(ssid))
            }
            return WiFiScan(networks: strongest.values.sorted { $0.rssi > $1.rssi }, unnamed: unnamed)
        }.value
    }

    static func setPower(_ on: Bool) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard let iface = CWWiFiClient.shared().interface() else { throw WiFiControlError.noInterface }
            try iface.setPower(on)
        }.value
    }

    /// 加入网络。password 为 nil 时用于开放网络，或让系统使用已保存的密码。
    static func join(ssid: String, password: String?) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard let iface = CWWiFiClient.shared().interface() else { throw WiFiControlError.noInterface }
            let matches = try iface.scanForNetworks(withName: ssid, includeHidden: false)
            guard let network = matches.max(by: { $0.rssiValue < $1.rssiValue }) else {
                throw WiFiControlError.notFound
            }
            try iface.associate(to: network, password: password)
        }.value
    }

    /// 开发用：只读地检查扫描是否可用、能不能看到网络名称，不改变任何 Wi-Fi 状态。
    static func debugSummary() async -> String {
        await Task.detached {
            guard let iface = CWWiFiClient.shared().interface() else { return "no interface" }
            let profiles = iface.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
            var lines = [
                "powered: \(iface.powerOn())",
                "current ssid visible: \(iface.ssid() != nil)",
                "known profiles: \(profiles.count), with names: \(profiles.filter { $0.ssid != nil }.count)",
            ]
            do {
                let started = Date()
                let results = try iface.scanForNetworks(withName: nil, includeHidden: false)
                let named = results.filter { $0.ssid?.isEmpty == false }
                lines.append("scan: \(results.count) results, \(named.count) with names, \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            } catch {
                lines.append("scan failed: \(error.localizedDescription)")
            }
            return lines.joined(separator: "\n")
        }.value
    }

    private static func describe(_ network: CWNetwork, ssid: String, known: Bool) -> WiFiNetwork {
        let open = network.supportsSecurity(CWSecurity.none)
        let passwordless = open || network.supportsSecurity(.OWE) || network.supportsSecurity(.oweTransition)
        let personal = [CWSecurity.WEP, .wpaPersonal, .wpaPersonalMixed, .wpa2Personal, .personal, .wpa3Personal, .wpa3Transition]
            .contains { network.supportsSecurity($0) }
        let enterprise = [CWSecurity.dynamicWEP, .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise, .wpa3Enterprise]
            .contains { network.supportsSecurity($0) }
        return WiFiNetwork(
            ssid: ssid,
            rssi: network.rssiValue,
            secure: !open,
            needsPassword: !passwordless,
            enterprise: enterprise && !personal && !passwordless,
            known: known
        )
    }
}
