import Foundation

/// "Malware removal" for a startup item: unload it, then move its plist (and its program, if the
/// program lives somewhere it's safe to remove from) to the Trash so it can be restored.
public enum LaunchItemRemover {
    public struct Plan: Sendable, Equatable {
        public let item: LaunchItem
        public let filesToTrash: [String]
        public let needsAdmin: Bool
    }

    static let adminRemovableRoots = ["/Library/LaunchAgents/", "/Library/LaunchDaemons/", "/Library/PrivilegedHelperTools/",
                                      "/Library/Application Support/", "/Users/Shared/", "/private/tmp/", "/tmp/"]

    public static func plan(for item: LaunchItem, home: String = NSHomeDirectory()) -> Plan {
        var files = [item.plistPath]
        if let program = item.executable, canRemoveProgram(program, home: home) { files.append(program) }
        let needsAdmin = files.contains { !PathTools.isDescendant($0, of: home) }
        return Plan(item: item, filesToTrash: files, needsAdmin: needsAdmin)
    }

    /// Never touch system binaries or interpreters (/bin/sh, /usr/bin/python3) a plist merely invokes.
    static func canRemoveProgram(_ program: String, home: String) -> Bool {
        guard FileManager.default.fileExists(atPath: program) else { return false }
        if PathTools.isDescendant(program, of: home) {
            return PathGuard.canRemove(program, home: home) && !program.contains(".app/")
        }
        return adminRemovableRoots.contains { program.hasPrefix($0) }
    }

    public static func execute(_ plan: Plan, home: String = NSHomeDirectory()) async throws {
        try? await LaunchControl.perform(.disable, on: plan.item)
        if plan.needsAdmin {
            let allowed = plan.filesToTrash.allSatisfy { path in
                PathTools.isDescendant(path, of: home) || adminRemovableRoots.contains { path.hasPrefix($0) }
            }
            guard allowed else { throw AdminRunner.AdminError.invalidInput }
            try await AdminRunner.moveToTrash(plan.filesToTrash, home: home)
        } else {
            let results = Cleaner.remove(plan.filesToTrash.map { CleanupTarget(path: $0, size: 0) }, mode: .trash, home: home)
            if let failure = results.first(where: { !$0.succeeded }) {
                throw AdminRunner.AdminError.failed("Couldn't move \(failure.path) to the Trash.")
            }
        }
    }
}
