import Darwin
import Foundation
import os

public enum LaunchAction: String, Sendable {
    case stop = "Stop"
    case disable = "Disable"
    case enable = "Enable"
}

public struct LaunchState: Sendable {
    public let statuses: [String: LaunchStatus]
    public let disabled: Set<String>

    public static let empty = LaunchState(statuses: [:], disabled: [])
}

public enum LaunchControl {
    private static let log = Logger(subsystem: Log.subsystem, category: "launchctl")

    static var userDomain: String { "gui/\(getuid())" }

    public static func readState() async -> LaunchState {
        async let list = try? Shell.run("/bin/launchctl", ["list"])
        async let disabled = try? Shell.run("/bin/launchctl", ["print-disabled", userDomain])
        let statuses = await list.map { LaunchctlParser.parseList($0.stdout) } ?? [:]
        let disabledLabels = await disabled.map { LaunchctlParser.parseDisabled($0.stdout) } ?? []
        return LaunchState(statuses: statuses, disabled: disabledLabels)
    }

    /// Daemons live in the system domain and go through the admin prompt; agents use your GUI domain.
    public static func perform(_ action: LaunchAction, on item: LaunchItem) async throws {
        let commands = commands(for: action, item: item, uid: getuid())
        log.info("\(action.rawValue, privacy: .public) \(item.label, privacy: .public)")
        for arguments in commands {
            if item.scope.requiresAdmin {
                try await AdminRunner.launchctl(arguments)
            } else {
                let result = try await Shell.run("/bin/launchctl", arguments)
                // bootout of something not loaded (status 3/36/113) is not a failure for "stop".
                if result.status != 0, arguments.first != "bootout" {
                    throw AdminRunner.AdminError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }

    static func commands(for action: LaunchAction, item: LaunchItem, uid: UInt32) -> [[String]] {
        let domain = item.scope.requiresAdmin ? "system" : "gui/\(uid)"
        switch action {
        case .stop:
            return [["bootout", domain, item.plistPath]]
        case .disable:
            return [["disable", "\(domain)/\(item.label)"], ["bootout", domain, item.plistPath]]
        case .enable:
            return [["enable", "\(domain)/\(item.label)"], ["bootstrap", domain, item.plistPath]]
        }
    }
}
