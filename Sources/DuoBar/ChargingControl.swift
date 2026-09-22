import Foundation
import ObjectiveC

/// 系统“优化电池充电”和“充电上限”现在的状态。
struct ChargeLimitState: Sendable, Equatable {
    /// 电量上限从哪来。
    enum Source: Sendable, Equatable {
        /// 优化电池充电：按使用习惯先停在上限，快到要用的时候再充满。
        case optimized
        /// 在“系统设置 › 电池”里手动设定的充电上限。
        case manual
    }

    /// 正在起作用的上限；nil 表示没有，会一直充到 100%。
    var source: Source?
    /// 上限（百分比）。
    var limit: Int
    /// 可以“立即充满电”。
    var canOverride: Bool
    /// 优化充电预计充满的时间。
    var deadline: Date?
}

/// 读取充电上限，以及执行“立即充满电”。
///
/// 用的是控制中心同款的私有接口（PowerUI 框架里的 PowerUISmartChargeClient），
/// 读取和“立即充满电”都不需要额外的权限。都是同步的跨进程调用，不要在主线程上用。
enum ChargingControl {
    /// PowerUI 不存在或接口变了时为 nil，面板里就不显示这些内容。
    nonisolated(unsafe) private static let client: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_LAZY) != nil,
              let type = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
              let allocated = (type as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let client = allocated.perform(NSSelectorFromString("initWithClientName:"), with: "DuoBar")?
                  .takeUnretainedValue() as? NSObject
        else { return nil }
        return client
    }()

    static func read() -> ChargeLimitState? {
        guard let client else { return nil }

        // 优化充电：是否在起作用、上限、能不能手动覆盖。
        typealias Engaged = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<ObjCBool>,
                                            UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<ObjCBool>,
                                            AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool
        var engaged: ObjCBool = false, optimizedLimit: UInt64 = 100, canOverride: ObjCBool = false
        var error: NSError?
        guard let engagedCall = function(client, "isOBCEngaged:chargeLimit:chargingOverrideAllowed:withError:",
                                         as: Engaged.self),
              engagedCall.function(client, engagedCall.selector, &engaged, &optimizedLimit, &canOverride, &error)
        else { return nil }

        // 界面状态里的“能不能覆盖”同时考虑了手动上限，以它为准。
        typealias UIState = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<UInt>,
                                            UnsafeMutablePointer<UInt>, UnsafeMutablePointer<ObjCBool>,
                                            AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool
        var mode: UInt = 0, uiLimit: UInt = 100, uiCanOverride: ObjCBool = false
        if let stateCall = function(client, "smartChargingUIState:chargeLimit:chargingOverrideAllowed:withError:",
                                    as: UIState.self),
           stateCall.function(client, stateCall.selector, &mode, &uiLimit, &uiCanOverride, &error) {
            canOverride = ObjCBool(canOverride.boolValue || uiCanOverride.boolValue)
        }

        // 手动上限：100 表示没有设。
        typealias Limit = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>) -> UInt8
        var manualLimit = 100
        if let limitCall = function(client, "getMCLLimitWithError:", as: Limit.self) {
            manualLimit = Int(limitCall.function(client, limitCall.selector, &error))
        }

        typealias Deadline = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>) -> AnyObject?
        var deadline: Date?
        if let deadlineCall = function(client, "fullChargeDeadline:", as: Deadline.self),
           let date = deadlineCall.function(client, deadlineCall.selector, &error) as? Date,
           date.timeIntervalSince1970 > 0 {
            deadline = date
        }

        if manualLimit > 0, manualLimit < 100 {
            return ChargeLimitState(source: .manual, limit: manualLimit, canOverride: canOverride.boolValue,
                                    deadline: nil)
        }
        if engaged.boolValue {
            return ChargeLimitState(source: .optimized, limit: Int(optimizedLimit), canOverride: canOverride.boolValue,
                                    deadline: deadline)
        }
        return ChargeLimitState(source: nil, limit: 100, canOverride: canOverride.boolValue, deadline: nil)
    }

    /// 和控制中心的“立即充满电”一样：手动上限临时解除，优化充电临时恢复充电。
    static func chargeToFullNow(_ state: ChargeLimitState) throws {
        guard let client else { throw ChargingError.unavailable }
        let selector = state.source == .manual ? "temporarilyDisableMCL:" : "temporarilyEnableCharging:"
        typealias Call = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool
        guard let call = function(client, selector, as: Call.self) else { throw ChargingError.unavailable }
        var error: NSError?
        guard call.function(client, call.selector, &error) else {
            if let error { throw error }
            throw ChargingError.unavailable
        }
    }

    enum ChargingError: LocalizedError {
        case unavailable

        var errorDescription: String? { "这台 Mac 上用不了“立即充满电”" }
    }

    /// 方法存在时返回它的函数指针。
    private static func function<F>(_ object: NSObject, _ name: String, as type: F.Type) -> (function: F, selector: Selector)? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return (unsafeBitCast(object.method(for: selector), to: type), selector)
    }
}
