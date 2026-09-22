import AppKit
import Darwin

/// 占用 CPU 较多的 App，对应系统电池菜单里的“使用大量能耗”。
struct EnergyHog: Sendable, Equatable, Identifiable {
    var pid: pid_t
    var name: String
    /// 最近一段时间的平均占用，单个核心占满是 100。
    var cpu: Double

    var id: pid_t { pid }
}

/// 系统的“使用大量能耗”没有公开接口，这里按 CPU 占用来估：
/// 每隔几秒读一次所有进程用掉的 CPU 时间，按“负责的 App”汇总（Safari 的网页进程算在 Safari 头上），
/// 平滑后超过门槛的普通 App 就列出来。
enum EnergyUsage {
    /// 平滑后的平均占用超过它才算“大量”。
    static let threshold: Double = 20

    struct Sample: Sendable {
        var uptime: UInt64
        /// 负责的进程 → 累计 CPU 时间（纳秒）
        var cpu: [pid_t: UInt64]
    }

    /// 读一次各进程累计的 CPU 时间，按负责的进程汇总。读不到的（别的用户、系统进程）跳过。
    static func sample() -> Sample {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let count = proc_listallpids(nil, 0)
        var pids = [pid_t](repeating: 0, count: max(Int(count), 0) + 64)
        let found = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))

        var totals: [pid_t: UInt64] = [:]
        for pid in pids.prefix(max(found, 0)) where pid > 0 {
            var info = rusage_info_v2()
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard status == 0 else { continue }
            // Apple 芯片上这两项的单位是 mach 时间，要换算成纳秒。
            let ticks = info.ri_user_time + info.ri_system_time
            let nanoseconds = ticks * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
            totals[responsible(for: pid), default: 0] += nanoseconds
        }
        return Sample(uptime: clock_gettime_nsec_np(CLOCK_UPTIME_RAW), cpu: totals)
    }

    /// 两次采样之间各负责进程的平均占用（单个核心占满是 100）。
    static func usage(from old: Sample, to new: Sample) -> [pid_t: Double] {
        let elapsed = Double(new.uptime &- old.uptime)
        guard elapsed > 0 else { return [:] }
        var result: [pid_t: Double] = [:]
        for (pid, now) in new.cpu {
            guard let before = old.cpu[pid], now >= before else { continue }
            result[pid] = Double(now - before) / elapsed * 100
        }
        return result
    }

    /// 负责这个进程的 App（比如 Safari 的网页进程由 Safari 负责）。系统没有公开这个接口，拿不到时就是它自己。
    private static func responsible(for pid: pid_t) -> pid_t {
        guard let lookup = responsibleLookup else { return pid }
        let owner = lookup(pid)
        return owner > 0 ? owner : pid
    }

    private typealias Lookup = @convention(c) (pid_t) -> pid_t
    private static let responsibleLookup: Lookup? = {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        return dlsym(defaultHandle, "responsibility_get_pid_responsible_for_pid").map { unsafeBitCast($0, to: Lookup.self) }
    }()
}
