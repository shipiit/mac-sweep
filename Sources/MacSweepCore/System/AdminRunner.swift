import Foundation

/// Runs a small, fixed set of privileged commands through the standard macOS admin password prompt.
/// Commands are assembled only from constants, integers and validated launchd labels.
public enum AdminRunner {
    public enum AdminError: Error, LocalizedError {
        case cancelled
        case invalidInput
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .cancelled: "Administrator authorisation was cancelled."
            case .invalidInput: "Refused to run a command with unexpected input."
            case .failed(let message): message
            }
        }
    }

    public static func kill(pid: Int32, signal: Int32) async throws {
        guard pid > 1 else { throw AdminError.invalidInput }
        _ = try await run("/bin/kill -\(signal) \(pid)")
    }

    /// Runs one of MacSweep's built-in constant commands (e.g. a MaintenanceTask) as administrator.
    static func runFixed(_ command: String) async throws -> String {
        try await run(command)
    }

    /// Moves files into the user's Trash as administrator (for root-owned startup items).
    public static func moveToTrash(_ paths: [String], home: String = NSHomeDirectory()) async throws {
        guard !paths.isEmpty, paths.allSatisfy({ $0.hasPrefix("/") && isSafeToken($0) }), isSafeToken(home) else {
            throw AdminError.invalidInput
        }
        let command = "/bin/mv " + paths.map(quote).joined(separator: " ") + " " + quote(home + "/.Trash/")
        _ = try await run(command)
    }

    /// Flushes the DNS cache and purges inactive memory under a single password prompt.
    public static func flushDNSAndPurgeMemory() async throws {
        _ = try await run("/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder; /usr/sbin/purge")
    }

    public static func purgeMemory() async throws {
        _ = try await run("/usr/sbin/purge")
    }

    public static func listeningPorts(includeUDP: Bool) async throws -> String {
        try await run("/usr/sbin/lsof " + PortScanner.lsofArguments(includeUDP: includeUDP).joined(separator: " "))
    }

    public static func launchctl(_ arguments: [String]) async throws {
        guard arguments.allSatisfy(isSafeToken) else { throw AdminError.invalidInput }
        _ = try await run("/bin/launchctl " + arguments.map(quote).joined(separator: " "))
    }

    static func isSafeToken(_ token: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-/ "))
        return !token.isEmpty && token.unicodeScalars.allSatisfy(allowed.contains)
    }

    static func quote(_ token: String) -> String {
        "'" + token.replacingOccurrences(of: "'", with: "") + "'"
    }

    static func appleScript(for command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    private static func run(_ command: String) async throws -> String {
        let result = try await Shell.run("/usr/bin/osascript", ["-e", appleScript(for: command)])
        if result.status == 0 { return result.stdout }
        if result.stderr.contains("-128") { throw AdminError.cancelled }
        throw AdminError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
