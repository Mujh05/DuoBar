import Foundation
import IOKit.ps

/// 读取内置电池状态，并在系统电源状态变化时回调。
@MainActor
final class BatteryMonitor {
    private(set) var info = BatteryInfo.placeholder
    var onChange: ((BatteryInfo) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?
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

    nonisolated static func read() -> BatteryInfo {
        var result = BatteryInfo.placeholder
        result.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

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
            return result
        }

        // 台式机没有电池：一直当作接着电源。
        return result
    }
}
