import Darwin
import Foundation
import IOKit.ps

struct BatteryInfo: Sendable {
    let percent: Double
    let isCharging: Bool
    let onACPower: Bool
}

/// Reads CPU, memory, disk and battery numbers with the same Mach and IOKit calls Activity Monitor uses.
enum SystemStats {
    struct CPUTicks {
        var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
    }

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // cpu_ticks is (user, system, idle, nice)
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    /// Busy fraction (0...1) between two samples. Tick counters wrap, so use wrapping subtraction.
    static func cpuUsage(from old: CPUTicks, to new: CPUTicks) -> Double {
        let user = Double(new.user &- old.user)
        let system = Double(new.system &- old.system)
        let nice = Double(new.nice &- old.nice)
        let idle = Double(new.idle &- old.idle)
        let busy = user + system + nice
        let total = busy + idle
        return total > 0 ? busy / total : 0
    }

    /// Returns (used, total) bytes. "Used" is app memory + wired + compressed, as in Activity Monitor.
    static func memory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)
        let appPages = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        let used = (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    /// Returns (free, total) bytes on the startup disk. "Free" includes purgeable space, as Finder shows it.
    static func disk() -> (free: Int64, total: Int64) {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return (values?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(values?.volumeTotalCapacity ?? 0))
    }

    static func battery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return BatteryInfo(
                percent: Double(current) / Double(max),
                isCharging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                onACPower: (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            )
        }
        return nil
    }
}
