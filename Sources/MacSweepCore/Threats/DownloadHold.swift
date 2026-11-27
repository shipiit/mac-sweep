import Foundation

/// How strict Download Protection is about files that pass every check.
public enum DownloadHoldMode: String, CaseIterable, Sendable, Identifiable {
    /// Only threats are stopped.
    case off
    /// Anything that can run or unpack code waits for approval.
    case programs
    /// Every new file waits for approval.
    case everything

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Only stop threats"
        case .programs: "Ask about apps, installers and scripts"
        case .everything: "Ask about every download"
        }
    }

    public var detail: String {
        switch self {
        case .off: "Downloads that pass the checks stay in your Downloads folder."
        case .programs: "Apps, installers, disk images, archives and scripts wait in quarantine until you allow them. Documents and media arrive as usual."
        case .everything: "Every new file in Downloads waits in quarantine until you allow it, including documents and files you save yourself."
        }
    }
}

/// Holds clean downloads in quarantine until the user says yes, so nothing new can be opened by accident.
public enum DownloadHold {
    /// The single reason on a held item; it's how held files are told apart from real threats.
    public static let reason = "Waiting for your OK"
    static let programKinds: Set<FileKind> = [.app, .installerPackage, .diskImage, .script, .executable, .archive]
    /// A file still being written is left alone until it has been quiet for this long.
    public static let settleTime: TimeInterval = 1.5

    public static func shouldHold(kind: FileKind, mode: DownloadHoldMode) -> Bool {
        switch mode {
        case .off: false
        case .programs: programKinds.contains(kind)
        case .everything: true
        }
    }

    public static func isSettled(modified: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(modified) >= settleTime
    }

    /// A harmless "verdict" that lets the quarantine store hold the file and remember where it came from.
    public static func verdict(path: String, kind: FileKind, origin: String?, size: UInt64) -> ThreatVerdict {
        ThreatVerdict(facts: FileFacts(path: path, kind: kind, signature: nil, origin: origin, size: size), severity: .info, reasons: [reason])
    }

    public static func isHeld(_ item: QuarantinedItem) -> Bool { item.reasons == [reason] }
}
