import Foundation
import os

/// An installed simulator runtime (e.g. iOS 26.5), each one a disk image of 5–20 GB outside your home folder.
public struct SimulatorRuntime: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let size: UInt64
    public let lastUsed: Date?
    public let isDeletable: Bool
}

public enum SimulatorRuntimes {
    private static let log = Logger(subsystem: Log.subsystem, category: "sim-runtimes")

    /// Parses `xcrun simctl runtime list -j`: a dictionary keyed by runtime UUID.
    public static func parse(_ data: Data) -> [SimulatorRuntime] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
        return json.compactMap { key, value -> SimulatorRuntime? in
            let identifier = value["identifier"] as? String ?? key
            guard UUID(uuidString: identifier) != nil else { return nil }
            let runtime = value["runtimeIdentifier"] as? String ?? ""
            let version = value["version"] as? String ?? ""
            let base = runtime.isEmpty ? (value["platformIdentifier"] as? String ?? "Simulator") : XcodeStorage.runtimeName(runtime)
            let name = runtime.isEmpty && !version.isEmpty ? "\(base) \(version)" : base
            let size = (value["sizeBytes"] as? NSNumber)?.uint64Value ?? 0
            let lastUsed = (value["lastUsedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            return SimulatorRuntime(id: identifier, name: name, size: size, lastUsed: lastUsed, isDeletable: value["deletable"] as? Bool ?? true)
        }
        .sorted { $0.size > $1.size }
    }

    public static func list() async -> [SimulatorRuntime] {
        guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun"),
              let result = try? await DevShell.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"], timeout: 30, tool: "simctl"),
              result.status == 0 else { return [] }
        return parse(Data(result.stdout.utf8))
    }

    /// Xcode offers to download a deleted runtime again when a project needs it.
    public static func delete(_ runtime: SimulatorRuntime) async throws {
        guard runtime.isDeletable, UUID(uuidString: runtime.id) != nil else { throw DevCommandError.invalidName(runtime.id) }
        let result = try await DevShell.run("/usr/bin/xcrun", ["simctl", "runtime", "delete", runtime.id], timeout: 120, tool: "simctl")
        guard result.status == 0 else { throw DevCommandError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        log.info("deleted simulator runtime (\(runtime.size) bytes)")
    }
}
