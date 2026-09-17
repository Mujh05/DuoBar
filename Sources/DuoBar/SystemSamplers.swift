import AudioToolbox // kAudioHardwareServiceDeviceProperty_VirtualMainVolume
import CFNetwork
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import IOKit

// 读取系统状态的小工具。全部是公开接口，不需要任何权限。

struct MemorySample: Sendable {
    var used: UInt64
    var total: UInt64
    /// kern.memorystatus_vm_pressure_level：1 正常，2 警告，4 严重
    var pressure: Int32
}

struct DiskSample: Sendable {
    var total: Int64
    var available: Int64
}

struct ThroughputSample: Sendable {
    /// 字节/秒
    var upload: Double
    var download: Double
}

struct AudioSample: Sendable {
    var level: Double
    var muted: Bool
    var deviceName: String?
    /// 声音正从蓝牙设备（比如 AirPods）播放。
    var bluetoothOutput: Bool
}

struct AccessoryBattery: Sendable, Equatable {
    var name: String
    var percent: Int
}

/// 每次调用 mach_host_self() 都会多占一个端口引用，取一次反复用。
private let hostPort = mach_host_self()

/// CPU 占用需要两次采样之间的差值。
struct CPUSampler {
    private var previous: [UInt32]?

    mutating func sample() -> Double? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // user, system, idle, nice
        let ticks = [load.cpu_ticks.0, load.cpu_ticks.1, load.cpu_ticks.2, load.cpu_ticks.3]
        defer { previous = ticks }
        guard let previous else { return nil }

        // 计数器是 32 位的，用溢出减法处理回绕。
        let deltas = zip(ticks, previous).map { UInt64($0 &- $1) }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        let idle = deltas[Int(CPU_STATE_IDLE)]
        return Double(total - idle) / Double(total)
    }
}

enum GPUReader {
    static func utilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let value = stats["Device Utilization %"] as? Int {
                best = max(best ?? 0, Double(value) / 100)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return best
    }
}

enum MemoryReader {
    static func read() -> MemorySample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = UInt64(getpagesize())
        let app = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page

        var pressure: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0) != 0 {
            pressure = 1
        }
        return MemorySample(used: used, total: ProcessInfo.processInfo.physicalMemory, pressure: pressure)
    }
}

enum DiskReader {
    static func read() -> DiskSample? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return DiskSample(total: Int64(total), available: available)
    }
}

/// 网速同样需要两次采样之间的差值。
struct ThroughputSampler {
    private var previous: (received: UInt64, sent: UInt64, time: TimeInterval)?

    mutating func sample() -> ThroughputSample? {
        guard let totals = Self.totals() else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previous = (totals.received, totals.sent, now) }
        guard let previous, now > previous.time else { return nil }

        let elapsed = now - previous.time
        // 网卡重置时计数器可能变小，这一次按 0 算。
        let received = totals.received >= previous.received ? totals.received - previous.received : 0
        let sent = totals.sent >= previous.sent ? totals.sent - previous.sent : 0
        return ThroughputSample(upload: Double(sent) / elapsed, download: Double(received) / elapsed)
    }

    /// 所有 en* 网卡（Wi-Fi、以太网、USB 共享网络）的累计收发字节数。
    /// VPN 的流量最终也走这些网卡，所以不重复统计 utun。
    private static func totals() -> (received: UInt64, sent: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var received: UInt64 = 0, sent: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr>.size
            while offset + headerSize <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(info.ifm_index), &name) != nil,
                       String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).hasPrefix("en") {
                        received += info.ifm_data.ifi_ibytes
                        sent += info.ifm_data.ifi_obytes
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return (received, sent)
    }
}

enum AudioReader {
    static func read() -> AudioSample? {
        guard let device = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) else { return nil }
        let name = deviceName(device)
        let transport = uint32(device, kAudioDevicePropertyTransportType)
        let bluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE

        // 虚拟主音量：设备没有主声道音量时，由系统换算各声道。
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let hasVolume = AudioObjectHasProperty(device, &address)
            && AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr
        let mute = uint32(device, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)

        // 有些设备（比如 HDMI 显示器）不能调音量，当作满音量。
        return AudioSample(level: hasVolume ? Double(min(max(volume, 0), 1)) : 1,
                           muted: (mute ?? 0) != 0, deviceName: name, bluetoothOutput: bluetooth)
    }

    private static func deviceName(_ device: AudioObjectID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        return status == noErr ? name?.takeRetainedValue() as String? : nil
    }

    static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        guard let device = uint32(AudioObjectID(kAudioObjectSystemObject), selector),
              device != kAudioObjectUnknown
        else { return nil }
        return device
    }

    static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(object, &address),
              AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
        else { return nil }
        return value
    }
}

extension AudioReader {
    /// 设置默认输出设备的音量（0...1），设备不能调音量时返回 false。
    @discardableResult
    static func setVolume(_ level: Double) -> Bool {
        var value = Float32(min(max(level, 0), 1))
        return set(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, to: &value)
    }

    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        var value = UInt32(muted ? 1 : 0)
        return set(kAudioDevicePropertyMute, to: &value)
    }

    private static func set<Value: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, to value: inout Value) -> Bool {
        guard let device = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) else { return false }
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
        else { return false }
        return withUnsafeBytes(of: &value) { bytes in
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(bytes.count), bytes.baseAddress!)
        } == noErr
    }
}

enum MicrophoneReader {
    /// 任何进程在用默认输入设备时为 true。读取这个状态不需要麦克风权限。
    static func inUse() -> Bool? {
        guard let device = AudioReader.defaultDevice(kAudioHardwarePropertyDefaultInputDevice) else { return false }
        return AudioReader.uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere).map { $0 != 0 }
    }
}

enum VPNReader {
    /// 系统代理设置里按网卡列出的条目；连着 VPN 时会出现 utun、ipsec、ppp 等隧道网卡。
    static func isActive() -> Bool? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return nil }
        let scoped = settings["__SCOPED__"] as? [String: Any] ?? [:]
        let prefixes = ["utun", "ipsec", "ppp", "tun", "tap", "wg"]
        return scoped.keys.contains { name in prefixes.contains { name.hasPrefix($0) } }
    }
}

enum DisplayReader {
    static func hasExternal() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
}

enum AccessoryReader {
    /// 妙控键盘、鼠标、触控板这类 Apple 蓝牙外设会在 IORegistry 里报告电量。
    static func read() -> [AccessoryBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [AccessoryBattery] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let percent = IORegistryEntryCreateCFProperty(entry, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int {
                let name = IORegistryEntryCreateCFProperty(entry, "Product" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String
                devices.append(AccessoryBattery(name: name ?? "蓝牙外设", percent: min(max(percent, 0), 100)))
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return devices.sorted { $0.name < $1.name }
    }
}
