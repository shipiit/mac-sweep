import Foundation
import os

public struct BrewCleanupPreview: Sendable, Equatable {
    public let reclaimable: UInt64
    public let itemCount: Int

    public init(reclaimable: UInt64, itemCount: Int) {
        self.reclaimable = reclaimable
        self.itemCount = itemCount
    }

    public static let empty = BrewCleanupPreview(reclaimable: 0, itemCount: 0)
}

public struct BrewSnapshot: Sendable, Equatable {
    public let outdated: [AvailableUpdate]
    public let cleanup: BrewCleanupPreview

    public init(outdated: [AvailableUpdate], cleanup: BrewCleanupPreview) {
        self.outdated = outdated
        self.cleanup = cleanup
    }

    public var outdatedFormulae: [AvailableUpdate] { outdated.filter { $0.source == .homebrewFormula } }
    public var outdatedCasks: [AvailableUpdate] { outdated.filter { $0.source == .homebrewCask } }
}

public enum BrewParser {
    /// Parses `brew cleanup -n`. The total comes from the "would free approximately X" footer;
    /// brew omits it when there is nothing to free.
    public static func parseCleanup(_ output: String) -> BrewCleanupPreview {
        var total: UInt64 = 0
        var count = 0
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("Would remove") { count += 1 }
            guard let start = line.range(of: "free approximately "), let end = line.range(of: " of disk space") else { continue }
            guard start.upperBound <= end.lowerBound else { continue }
            total = HumanSize.parse(String(line[start.upperBound..<end.lowerBound])) ?? total
        }
        return BrewCleanupPreview(reclaimable: total, itemCount: count)
    }
}

public enum Homebrew {
    private static let log = Logger(subsystem: Log.subsystem, category: "homebrew")

    public static func snapshot() async throws -> BrewSnapshot {
        guard let brew = Updater.brewPath else { throw DevCommandError.notInstalled("Homebrew") }
        async let outdated = DevShell.brew(brew, ["outdated", "--json=v2"])
        async let cleanup = DevShell.brew(brew, ["cleanup", "-n"])
        let outdatedResult = try await outdated
        let cleanupResult = try await cleanup
        return BrewSnapshot(outdated: Updater.parseBrewOutdated(outdatedResult.stdout),
                            cleanup: BrewParser.parseCleanup(cleanupResult.stdout))
    }

    public static func runCleanup() async throws {
        guard let brew = Updater.brewPath else { throw DevCommandError.notInstalled("Homebrew") }
        log.info("running brew cleanup")
        let result = try await DevShell.brew(brew, ["cleanup"], timeout: 600)
        guard result.status == 0 else { throw DevCommandError.failed(DockerClient.firstLine(result.stderr)) }
    }
}
