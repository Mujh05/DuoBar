import Foundation
import IOKit
import IOKit.ps
import notify

/// 读取内置电池状态，并在系统电源状态变化时回调。
@MainActor
final class BatteryMonitor {
    private(set) var info = BatteryInfo.placeholder
    var onChange: ((BatteryInfo) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?
    private var highPowerToken: Int32 = NOTIFY_TOKEN_INVALID
    private var pollTask: Task<Void, Never>?

    func start() {
        refresh()

        // 电量、电源适配器插拔等变化由 IOKit 主动通知。回调发生在主线程的 run loop 上。
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }

        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // 高电量模式没有公开的通知，系统用这个 notify 名字广播。
        notify_register_dispatch(Self.highPowerModeName, &highPowerToken, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        // 剩余时间的估算不一定触发通知，低频轮询兜底。
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
                self?.refresh()
            }
        }
    }

    func refresh() {
        let new = Self.read()
        guard new != info else { return }
        info = new
        onChange?(new)
    }

    private nonisolated static let highPowerModeName = "com.apple.system.highpowermode"

    nonisolated static func read() -> BatteryInfo {
        var result = BatteryInfo.placeholder
        result.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        result.highPowerMode = notifyState(highPowerModeName) != 0

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return result }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  desc[kIOPSIsPresentKey] as? Bool ?? true
            else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let onAC = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let toEmpty = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            let toFull = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1

            result.hasBattery = true
            result.percent = max > 0 ? min(100, Int((Double(current) * 100 / Double(max)).rounded())) : 0
            result.power = !onAC ? .battery : (charging ? .charging : .pluggedIn)
            result.isCharged = desc[kIOPSIsChargedKey] as? Bool ?? false
            result.minutesToEmpty = !onAC && toEmpty > 0 ? toEmpty : nil
            result.minutesToFull = charging && toFull > 0 ? toFull : nil
            // 电池没问题时系统不给这两项。
            result.serviceRecommended = desc[kIOPSBatteryHealthConditionKey] != nil
                || desc[kIOPSBatteryHealthKey] as? String == kIOPSPoorValue
            result.slowCharger = onAC && (chargerData()?["SlowChargingReason"] as? Int ?? 0) != 0
            return result
        }

        // 台式机没有电池：一直当作接着电源。
        return result
    }

    /// 电池控制器报告的充电情况，比如为什么充得慢、为什么没在充。
    private nonisolated static func chargerData() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "ChargerData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
    }

    private nonisolated static func notifyState(_ name: String) -> UInt64 {
        var token: Int32 = 0
        guard notify_register_check(name, &token) == NOTIFY_STATUS_OK else { return 0 }
        defer { notify_cancel(token) }
        var state: UInt64 = 0
        notify_get_state(token, &state)
        return state
    }
}
