import Foundation

/// Parses the human-readable sizes printed by developer CLIs ("2.4GB", "512 kB", "0B", "1.5GiB").
/// Docker and Homebrew both use decimal units; the IEC "iB" forms are binary.
public enum HumanSize {
    public static func parse(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // Docker appends the share of the total in parentheses, e.g. "1.2GB (50%)".
        let raw = trimmed.split(separator: "(").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let numberEnd = raw.firstIndex { !($0.isNumber || $0 == ".") } ?? raw.endIndex
        guard let value = Double(raw[..<numberEnd]), value >= 0 else { return nil }
        let unit = raw[numberEnd...].trimmingCharacters(in: .whitespaces).lowercased()
        guard let multiplier = multipliers[unit] else { return nil }
        let bytes = value * multiplier
        guard bytes.isFinite, bytes < Double(UInt64.max) else { return nil }
        return UInt64(bytes.rounded())
    }

    private static let multipliers: [String: Double] = [
        "": 1, "b": 1,
        "k": 1e3, "kb": 1e3, "m": 1e6, "mb": 1e6, "g": 1e9, "gb": 1e9, "t": 1e12, "tb": 1e12,
        "kib": 1024, "mib": 1_048_576, "gib": 1_073_741_824, "tib": 1_099_511_627_776,
    ]
}

/// A cheap lookup for command-line tools; GUI apps don't inherit the shell's PATH.
public enum ToolLocator {
    public static func first(_ candidates: [String], isExecutable: (String) -> Bool = FileManager.default.isExecutableFile) -> String? {
        candidates.first(where: isExecutable)
    }

    /// Names that are safe to pass to brew, launchctl or simctl as a single argument.
    public static func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 200, !value.hasPrefix("-") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@._+-/"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) && $0.isASCII }
    }
}

public enum DevCommandError: Error, LocalizedError, Equatable {
    case notInstalled(String)
    case timedOut(String)
    case failed(String)
    case invalidName(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let tool): "\(tool) isn't installed."
        case .timedOut(let tool): "\(tool) didn't answer in time."
        case .failed(let message): message.isEmpty ? "The command failed." : message
        case .invalidName(let name): "Refusing an unexpected name: \(name)"
        }
    }
}

public enum DevShell {
    /// Runs a command but stops waiting after `seconds`, so a wedged daemon can't stall the UI.
    /// A task group would wait for the uncancellable child, hence the unstructured race.
    public static func run(_ executable: String, _ arguments: [String], timeout seconds: Double, tool: String) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            Task.detached {
                do {
                    let result = try await Shell.run(executable, arguments)
                    if once.claim() { continuation.resume(returning: result) }
                } catch {
                    if once.claim() { continuation.resume(throwing: error) }
                }
            }
            Task.detached {
                try? await Task.sleep(for: .seconds(seconds))
                if once.claim() { continuation.resume(throwing: DevCommandError.timedOut(tool)) }
            }
        }
    }

    /// Wraps brew so it never auto-updates or prints hints while we only read state.
    public static func brewArguments(_ brew: String, _ arguments: [String]) -> [String] {
        ["HOMEBREW_NO_AUTO_UPDATE=1", "HOMEBREW_NO_ENV_HINTS=1", "HOMEBREW_NO_INSTALL_CLEANUP=1", brew] + arguments
    }

    public static func brew(_ brew: String, _ arguments: [String], timeout: Double = 120) async throws -> ShellResult {
        try await run("/usr/bin/env", brewArguments(brew, arguments), timeout: timeout, tool: "Homebrew")
    }
}

final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// True for the first caller only.
    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
