import Foundation

public struct AvailableUpdate: Identifiable, Sendable, Equatable {
    public enum Source: String, Sendable {
        case macOS = "macOS"
        case homebrewCask = "Homebrew app"
        case homebrewFormula = "Homebrew tool"
    }

    public let name: String
    public let installed: String
    public let available: String
    public let source: Source
    public let needsRestart: Bool

    public var id: String { source.rawValue + "/" + name }
}

public enum Updater {
    public static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    public static var brewPath: String? {
        brewPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func check() async -> [AvailableUpdate] {
        async let system = try? Shell.run("/usr/sbin/softwareupdate", ["--list"])
        var updates = parseSoftwareUpdate(await system?.stdout ?? "")
        if let brew = brewPath, let result = try? await Shell.run(brew, ["outdated", "--json=v2", "--greedy-auto-updates"]) {
            updates += parseBrewOutdated(result.stdout)
        }
        return updates
    }

    /// Upgrades one Homebrew package. Names come from brew's own output and are validated.
    public static func upgrade(_ update: AvailableUpdate) async throws -> String {
        guard update.source != .macOS, let brew = brewPath,
              update.name.allSatisfy({ $0.isLetter || $0.isNumber || "-_.@/+".contains($0) })
        else { throw AdminRunner.AdminError.invalidInput }
        let arguments = update.source == .homebrewCask ? ["upgrade", "--cask", update.name] : ["upgrade", update.name]
        let result = try await Shell.run(brew, arguments)
        if result.status != 0 { throw AdminRunner.AdminError.failed(result.stderr) }
        return result.stdout
    }

    /// Parses `softwareupdate --list`: "* Label: X" followed by "Title: …, Version: …, …, Action: restart".
    public static func parseSoftwareUpdate(_ output: String) -> [AvailableUpdate] {
        var updates: [AvailableUpdate] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t,"))
            guard trimmed.hasPrefix("Title:") else { continue }
            var fields: [String: String] = [:]
            for part in trimmed.components(separatedBy: ", ") {
                let pair = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if pair.count == 2 { fields[pair[0]] = pair[1] }
            }
            guard let title = fields["Title"] else { continue }
            updates.append(AvailableUpdate(name: title, installed: "", available: fields["Version"] ?? "",
                                           source: .macOS, needsRestart: fields["Action"] == "restart"))
        }
        return updates
    }

    public static func parseBrewOutdated(_ json: String) -> [AvailableUpdate] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        func entries(_ key: String, _ source: AvailableUpdate.Source) -> [AvailableUpdate] {
            (root[key] as? [[String: Any]] ?? []).compactMap { entry in
                guard let name = entry["name"] as? String else { return nil }
                let installed = (entry["installed_versions"] as? [String])?.last ?? entry["installed_versions"] as? String ?? ""
                return AvailableUpdate(name: name, installed: installed, available: entry["current_version"] as? String ?? "",
                                       source: source, needsRestart: false)
            }
        }
        return entries("casks", .homebrewCask) + entries("formulae", .homebrewFormula)
    }
}
