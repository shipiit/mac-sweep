import Darwin
import Foundation
import os

public enum KillOutcome: Sendable, Equatable {
    case sent
    case refused(String)
    case notPermitted
    case notFound
    case failed(Int32)
}

public enum ProcessKiller {
    private static let log = Logger(subsystem: Log.subsystem, category: "killer")

    /// Killing any of these logs you out, hangs the Mac or panics the kernel.
    public static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "logind", "opendirectoryd",
        "securityd", "trustd", "configd", "diskarbitrationd", "fseventsd", "mds", "notifyd",
        "powerd", "syslogd", "UserEventAgent", "coreservicesd", "watchdogd", "kextd", "kernelmanagerd",
    ]

    public static func refusalReason(pid: Int32, name: String) -> String? {
        if pid <= 1 { return "Core system process." }
        if pid == getpid() { return "That's MacSweep itself." }
        if protectedNames.contains(name) { return "\(name) is critical to macOS. Killing it would crash or log you out." }
        return nil
    }

    public static func send(_ signal: Int32, to pid: Int32, name: String) -> KillOutcome {
        if let reason = refusalReason(pid: pid, name: name) { return .refused(reason) }
        guard Darwin.kill(pid, signal) == 0 else {
            let code = errno
            log.warning("signal \(signal) to pid \(pid) failed: errno \(code)")
            switch code {
            case EPERM: return .notPermitted
            case ESRCH: return .notFound
            default: return .failed(code)
            }
        }
        log.info("sent signal \(signal) to pid \(pid) (\(name, privacy: .public))")
        return .sent
    }
}
