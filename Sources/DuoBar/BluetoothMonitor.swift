import CoreBluetooth

/// 蓝牙开关状态。CoreBluetooth 是唯一的公开接口，第一次使用时系统会询问蓝牙权限。
/// 只在“蓝牙”指示灯用上时才启动，不扫描也不连接任何设备。
@MainActor
final class BluetoothMonitor: NSObject {
    enum Access: Sendable {
        case notDetermined, granted, denied
    }

    /// true 打开，false 关闭，nil 未知（没授权、不支持）。
    var onChange: ((Bool?) -> Void)?
    private var manager: CBCentralManager?

    static var access: Access {
        switch CBManager.authorization {
        case .allowedAlways: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    var isRunning: Bool { manager != nil }

    func start() {
        guard manager == nil else { return }
        manager = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func stop() {
        manager?.delegate = nil
        manager = nil
    }
}

extension BluetoothMonitor: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: onChange?(true)
        case .poweredOff: onChange?(false)
        default: onChange?(nil)
        }
    }
}
