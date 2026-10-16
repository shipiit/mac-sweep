import Foundation

public enum FindingSeverity: Int, Sendable, Comparable, CaseIterable {
    case info = 0
    case low = 1
    case medium = 2
    case high = 3

    public var title: String {
        switch self {
        case .info: "Info"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct SecurityFinding: Identifiable, Sendable, Equatable {
    public enum Subject: Sendable, Equatable {
        case launchItem(plistPath: String, label: String)
        case process(pid: Int32)
        case file(String)
    }

    public let severity: FindingSeverity
    public let title: String
    public let detail: String
    public let path: String?
    public let subject: Subject

    public var id: String { title + "|" + (path ?? "") + "|\(subject)" }
}

/// Heuristic persistence and process audit. Flags what malware typically does on macOS (hide in temp
/// or dot-folders, run unsigned at login, impersonate Apple) without claiming to be an antivirus.
public enum SecurityAudit {
    public static let knownAdwareMarkers = [
        "mackeeper", "genieo", "vsearch", "searchup", "pcvark", "mughthesec", "advancedmaccleaner",
        "macupdater.helper", "spigot", "installmac", "operativeupdate", "searchmine", "safefinder",
    ]

    /// World-writable or download locations. Tool caches (~/Library/Caches) are deliberately excluded:
    /// Playwright, Puppeteer and many CLIs legitimately run binaries from there.
    static let suspiciousLocations = ["/tmp/", "/private/tmp/", "/private/var/tmp/", "/users/shared/", "/downloads/"]

    public static func auditLaunchItems(_ items: [LaunchItem], signature: (String) -> SignatureStatus = CodeSignature.check) -> [SecurityFinding] {
        items.flatMap { item -> [SecurityFinding] in
            let subject = SecurityFinding.Subject.launchItem(plistPath: item.plistPath, label: item.label)
            var findings: [SecurityFinding] = []
            let lowerLabel = item.label.lowercased()
            let program = item.executable
            let lowerProgram = program?.lowercased() ?? ""

            if let marker = knownAdwareMarkers.first(where: { lowerLabel.contains($0) || lowerProgram.contains($0) }) {
                findings.append(.init(severity: .high, title: "Known adware: \(item.label)",
                                      detail: "Matches the known adware/PUP name “\(marker)”. Disable it and remove the app it came with.",
                                      path: item.plistPath, subject: subject))
            }
            guard let program else {
                return findings
            }
            let status = signature(program)
            if lowerLabel.hasPrefix("com.apple."), status != .apple, status != .missing {
                findings.append(.init(severity: .high, title: "Pretends to be Apple: \(item.label)",
                                      detail: "Uses an Apple-style name but its program isn't signed by Apple (\(status.title)). Real Apple agents don't live here.",
                                      path: program, subject: subject))
            }
            if let place = suspiciousLocations.first(where: { lowerProgram.contains($0) }) {
                findings.append(.init(severity: .high, title: "Starts from a temporary folder",
                                      detail: "\(item.label) runs a program inside \(place). Legitimate software doesn't run at login from there.",
                                      path: program, subject: subject))
            }
            if program.split(separator: "/").dropLast().contains(where: { $0.hasPrefix(".") && $0 != ".." }) || (program as NSString).lastPathComponent.hasPrefix(".") {
                findings.append(.init(severity: .medium, title: "Runs hidden program at login",
                                      detail: "\(item.label) launches a program inside a hidden folder. Check that you recognise it.",
                                      path: program, subject: subject))
            }
            switch status {
            case .missing:
                findings.append(.init(severity: .low, title: "Leftover startup item",
                                      detail: "\(item.label) points to a program that no longer exists. Usually left behind by an uninstalled app. Safe to disable.",
                                      path: item.plistPath, subject: subject))
            case .unsigned, .invalid:
                findings.append(.init(severity: item.runAtLoad || item.keepAlive ? .medium : .low,
                                      title: "\(status.title) program at login",
                                      detail: "\(item.label) starts \((program as NSString).lastPathComponent), which has no valid code signature.",
                                      path: program, subject: subject))
            default:
                break
            }
            return findings
        }
    }

    /// One finding per untrusted executable in a suspicious location, however many copies are running.
    public static func auditProcesses(_ processes: [ProcessSnapshot], signature: (String) -> SignatureStatus = CodeSignature.check) -> [SecurityFinding] {
        let grouped = Dictionary(grouping: processes.filter { $0.path != nil }) { $0.path ?? "" }
        return grouped.keys.sorted().compactMap { path -> SecurityFinding? in
            let lower = path.lowercased()
            guard let place = suspiciousLocations.first(where: { lower.contains($0) }),
                  let instances = grouped[path], let first = instances.first
            else { return nil }
            let status = signature(path)
            guard !status.isTrusted else { return nil }
            let isTemp = place.contains("tmp")
            let count = instances.count > 1 ? " (\(instances.count) processes)" : ""
            return SecurityFinding(severity: isTemp ? .high : .medium,
                                   title: "Running from \(isTemp ? "a temporary folder" : place.trimmingCharacters(in: CharacterSet(charactersIn: "/")).capitalized): \(first.name)\(count)",
                                   detail: "Runs from \(place) and is \(status.title.lowercased()). Make sure you started it yourself.",
                                   path: path, subject: .process(pid: first.pid))
        }
    }
}
