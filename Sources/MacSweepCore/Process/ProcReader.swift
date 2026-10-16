import Darwin
import Foundation

public struct ProcessSnapshot: Identifiable, Sendable, Hashable {
    public let pid: Int32
    public let ppid: Int32
    public let name: String
    public let path: String?
    public let uid: UInt32
    public let user: String
    /// Physical footprint (what Activity Monitor calls "Memory"). Nil when not permitted.
    public let memory: UInt64?
    public let cpuTimeNanos: UInt64?
    public let threads: Int?
    public let started: Date?

    public var id: Int32 { pid }

    public init(pid: Int32, ppid: Int32, name: String, path: String?, uid: UInt32, user: String,
                memory: UInt64?, cpuTimeNanos: UInt64?, threads: Int?, started: Date?) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.path = path
        self.uid = uid
        self.user = user
        self.memory = memory
        self.cpuTimeNanos = cpuTimeNanos
        self.threads = threads
        self.started = started
    }
}

/// Thin wrappers over libproc. Everything returns nil instead of failing when the
/// kernel refuses access (processes owned by other users without root).
public enum ProcReader {
    public static func allPIDs() -> [Int32] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 128)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<Int32>.size))
        }
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).filter { $0 > 0 }
    }

    public static func snapshot(pid: Int32, userNames: inout [UInt32: String]) -> ProcessSnapshot? {
        guard let bsd = bsdInfo(pid) else { return nil }
        let path = executablePath(pid)
        let shortName = cString(bsd.pbi_name)
        let name = shortName.isEmpty ? cString(bsd.pbi_comm) : shortName
        let usage = resourceUsage(pid)
        let uid = bsd.pbi_uid
        let user = userNames[uid] ?? userName(uid)
        userNames[uid] = user
        return ProcessSnapshot(
            pid: pid,
            ppid: Int32(bsd.pbi_ppid),
            name: displayName(name: name, path: path),
            path: path,
            uid: uid,
            user: user,
            memory: usage.map { $0.ri_phys_footprint },
            cpuTimeNanos: usage.map { machToNanos($0.ri_user_time &+ $0.ri_system_time) },
            threads: taskInfo(pid).map { Int($0.pti_threadnum) },
            started: bsd.pbi_start_tvsec > 0 ? Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec)) : nil
        )
    }

    public static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public static func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = cString(info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    /// Prefer the bundle or binary name from the path, since `pbi_name` is truncated to 32 bytes.
    static func displayName(name: String, path: String?) -> String {
        guard let path else { return name }
        if let range = path.range(of: ".app/Contents/MacOS/") {
            let bundle = (String(path[..<range.lowerBound]) as NSString).lastPathComponent
            let binary = (path as NSString).lastPathComponent
            return binary == bundle ? bundle : binary
        }
        let binary = (path as NSString).lastPathComponent
        return binary.count > name.count && binary.hasPrefix(name) ? binary : name
    }

    static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    static func taskInfo(_ pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size ? info : nil
    }

    static func resourceUsage(_ pid: Int32) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return status == 0 ? info : nil
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func machToNanos(_ ticks: UInt64) -> UInt64 {
        guard timebase.denom > 0 else { return ticks }
        return UInt64(Double(ticks) * Double(timebase.numer) / Double(timebase.denom))
    }

    static func userName(_ uid: UInt32) -> String {
        guard let entry = getpwuid(uid), let name = entry.pointee.pw_name else { return String(uid) }
        return String(cString: name)
    }

    /// Reads a fixed-size C char tuple up to its first NUL.
    static func cString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
