import Foundation

public struct BackupDestination: Identifiable, Sendable, Equatable {
    public let name: String
    public let kind: String?
    public let mountPoint: String?
    public let id: String
}

public enum ExclusionState: Sendable, Equatable {
    case included
    case excluded
    case unknown
}

/// Parsers for `tmutil`. Its exit codes are unreliable (0 on mount errors and with no destinations),
/// so every verdict is drawn from the text itself.
public enum TimeMachineParser {
    /// `tmutil latestbackup` prints a snapshot path ending in `YYYY-MM-DD-HHMMSS[.backup]`, in local time.
    public static func latestBackupDate(_ output: String, timeZone: TimeZone = .current) -> Date? {
        guard let match = output.firstMatch(of: #/(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})/#) else { return nil }
        var components = DateComponents()
        components.timeZone = timeZone
        components.year = Int(match.output.1)
        components.month = Int(match.output.2)
        components.day = Int(match.output.3)
        components.hour = Int(match.output.4)
        components.minute = Int(match.output.5)
        components.second = Int(match.output.6)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: components), components.isValidDate(in: calendar) else { return nil }
        return date
    }

    /// `tmutil destinationinfo`: blocks of `Key : Value` lines separated by `====` rules.
    public static func destinations(_ output: String) -> [BackupDestination] {
        var result: [BackupDestination] = []
        var fields: [String: String] = [:]

        func flush() {
            defer { fields = [:] }
            guard let id = fields["ID"] ?? fields["Name"] else { return }
            result.append(BackupDestination(name: fields["Name"] ?? "Backup disk", kind: fields["Kind"], mountPoint: fields["Mount Point"], id: id))
        }

        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("====") {
                flush()
                continue
            }
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[0].hasPrefix("tmutil") else { continue }
            fields[parts[0]] = parts[1]
        }
        flush()
        return result
    }

    /// `tmutil isexcluded a b …`: one `[Included]`, `[Excluded]` or `[UNKNOWN]` line per path.
    public static func exclusions(_ output: String) -> [String: ExclusionState] {
        var result: [String: ExclusionState] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let tag = line[line.index(after: line.startIndex)..<close].lowercased()
            let path = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            result[path] = tag == "included" ? .included : tag == "excluded" ? .excluded : .unknown
        }
        return result
    }

    public static func mentionsFullDiskAccess(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("full disk access") || lower.contains("operation not permitted")
    }
}

public struct BackupReport: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case notConfigured
        case needsFullDiskAccess
        case neverCompleted
        case backedUp(Date)
    }

    public let status: Status
    public let destinations: [BackupDestination]
    public let folders: [String: ExclusionState]

    public init(status: Status, destinations: [BackupDestination], folders: [String: ExclusionState]) {
        self.status = status
        self.destinations = destinations
        self.folders = folders
    }
}

public enum BackupAssessment {
    public static func status(destinations: [BackupDestination], latest: String, timeZone: TimeZone = .current) -> BackupReport.Status {
        if let date = TimeMachineParser.latestBackupDate(latest, timeZone: timeZone) { return .backedUp(date) }
        if TimeMachineParser.mentionsFullDiskAccess(latest) { return .needsFullDiskAccess }
        return destinations.isEmpty ? .notConfigured : .neverCompleted
    }

    /// Backup age: a day is normal for laptops; a week is worth a nudge; two weeks is a real gap.
    public static func ageSeverity(_ status: BackupReport.Status, now: Date = Date()) -> FindingSeverity {
        switch status {
        case .notConfigured, .neverCompleted: return .high
        case .needsFullDiskAccess: return .info
        case .backedUp(let date):
            let days = now.timeIntervalSince(date) / 86_400
            if days <= 1.1 { return .info }
            if days <= 7 { return .low }
            if days <= 14 { return .medium }
            return .high
        }
    }

    /// Folders whose loss would hurt most, keeping only those that exist.
    public static func importantFolders(home: String, exists: (String) -> Bool) -> [String] {
        let names = ["Documents", "Desktop", "Pictures", "Projects", "projects", "Developer", "Code", "code", "src", "dev", "work", "Sites"]
        var seen = Set<String>()
        return names.map { home + "/" + $0 }
            .filter { exists($0) && seen.insert($0.lowercased()).inserted }
    }

    public static func excludedImportant(_ folders: [String: ExclusionState]) -> [String] {
        folders.filter { $0.value == .excluded }.map(\.key).sorted()
    }
}

public enum BackupReader {
    public static func read(home: String = NSHomeDirectory()) async -> BackupReport {
        async let latest = try? Shell.run("/usr/bin/tmutil", ["latestbackup"])
        async let info = try? Shell.run("/usr/bin/tmutil", ["destinationinfo"])
        let folders = BackupAssessment.importantFolders(home: home) { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        let exclusions = folders.isEmpty ? nil : try? await Shell.run("/usr/bin/tmutil", ["isexcluded"] + folders)
        let destinations = TimeMachineParser.destinations(await info?.stdout ?? "")
        let latestResult = await latest
        return BackupReport(
            status: BackupAssessment.status(destinations: destinations, latest: (latestResult?.stdout ?? "") + "\n" + (latestResult?.stderr ?? "")),
            destinations: destinations,
            folders: TimeMachineParser.exclusions(exclusions?.stdout ?? "")
        )
    }
}
