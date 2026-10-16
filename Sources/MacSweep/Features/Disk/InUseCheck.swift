import AppKit
import MacSweepCore

enum InUseCheck {
    /// Gathers running processes (with working directories) and apps, then matches them against targets.
    static func run(targets: [String], home: String) async -> [InUseConflict] {
        let apps = NSWorkspace.shared.runningApplications.map {
            RunningAppInfo(name: $0.localizedName ?? "", bundleID: $0.bundleIdentifier)
        }
        let conflicts = await Task.detached(priority: .userInitiated) {
            let processes = ProcessSampler.sample().map {
                RunningProcessInfo(pid: $0.pid, name: $0.name, executable: $0.path, workingDirectory: ProcReader.workingDirectory($0.pid),
                                   arguments: ProcArgs.arguments(pid: $0.pid) ?? [])
            }
            return InUseDetector.conflicts(targets: targets, processes: processes, apps: apps, home: home)
        }.value
        MemoryRelief.release()
        return conflicts
    }
}
