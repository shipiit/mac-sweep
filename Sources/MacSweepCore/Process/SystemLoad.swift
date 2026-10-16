import Darwin
import Foundation

public struct CPUTicks: Sendable, Equatable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    var busy: UInt64 { user + system + nice }
    var total: UInt64 { busy + idle }
}

public struct NetworkCounters: Sendable, Equatable {
    public let received: UInt64
    public let sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }
}

public enum SystemLoad {
    /// Cumulative CPU ticks across all cores since boot.
    public static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return CPUTicks(
            user: UInt64(ticks.0), system: UInt64(ticks.1), idle: UInt64(ticks.2), nice: UInt64(ticks.3)
        )
    }

    /// Fraction 0...1 of CPU time spent busy between two readings.
    public static func usage(from previous: CPUTicks, to current: CPUTicks) -> Double {
        guard current.total > previous.total, current.busy >= previous.busy else { return 0 }
        let busy = Double(current.busy - previous.busy)
        let total = Double(current.total - previous.total)
        return min(max(busy / total, 0), 1)
    }

    /// Bytes in/out summed over physical interfaces (loopback excluded).
    public static func networkCounters() -> NetworkCounters? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  (entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  let data = entry.pointee.ifa_data
            else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(stats.ifi_ibytes)
            sent += UInt64(stats.ifi_obytes)
        }
        return NetworkCounters(received: received, sent: sent)
    }

    /// Bytes per second between two readings; counter wrap-around reads as zero rather than negative.
    public static func rate(from previous: UInt64, to current: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }

    public static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loads, 3)
        return count > 0 ? Array(loads.prefix(Int(count))) : []
    }
}
