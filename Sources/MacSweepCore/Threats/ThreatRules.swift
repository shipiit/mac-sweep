import Foundation

/// What kind of file this is, from its extension, executable bit and Mach-O magic.
public enum FileKind: String, Sendable, Equatable {
    case app, installerPackage, diskImage, script, executable, archive, document, other

    /// Scripts that macOS runs in Terminal on a double-click; other scripts just open in an editor.
    public static let runOnOpenExtensions: Set<String> = ["command", "tool", "terminal"]
    static let scriptExtensions: Set<String> = ["command", "sh", "zsh", "bash", "tool", "scpt", "applescript", "terminal", "py", "pl", "rb", "js", "jar"]
    static let documentExtensions: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "jpg", "jpeg", "png", "gif",
                                                  "heic", "mp3", "mp4", "mov", "csv", "pages", "numbers", "key", "zip"]
    static let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]

    public static func classify(name: String, isExecutable: Bool, isMachO: Bool) -> FileKind {
        switch (name as NSString).pathExtension.lowercased() {
        case "app": return .app
        case "pkg", "mpkg": return .installerPackage
        case "dmg", "iso": return .diskImage
        case let ext where scriptExtensions.contains(ext): return .script
        case let ext where archiveExtensions.contains(ext): return .archive
        case let ext where documentExtensions.contains(ext): return .document
        default: return isMachO || isExecutable ? .executable : .other
        }
    }
}

public enum GatekeeperVerdict: Sendable, Equatable {
    case accepted, rejected(String), notChecked
}

/// Everything the rules look at. Built by the scanner; pure data so the rules are testable.
public struct FileFacts: Sendable, Equatable {
    public let path: String
    public let kind: FileKind
    public let signature: SignatureStatus?
    public let gatekeeper: GatekeeperVerdict
    /// Where the file was downloaded from (com.apple.quarantine / kMDItemWhereFroms), when known.
    public let origin: String?
    public let isQuarantined: Bool
    public let size: UInt64

    public init(path: String, kind: FileKind, signature: SignatureStatus?, gatekeeper: GatekeeperVerdict = .notChecked,
                origin: String? = nil, isQuarantined: Bool = false, size: UInt64 = 0) {
        self.path = path
        self.kind = kind
        self.signature = signature
        self.gatekeeper = gatekeeper
        self.origin = origin
        self.isQuarantined = isQuarantined
        self.size = size
    }

    public var name: String { (path as NSString).lastPathComponent }
}

public struct ThreatVerdict: Sendable, Equatable, Identifiable {
    public let facts: FileFacts
    public let severity: FindingSeverity
    public let reasons: [String]
    public var id: String { facts.path }
    /// Only clear-cut cases are moved to quarantine automatically; the rest are reported.
    public var isAutoQuarantine: Bool { severity == .high }
}

/// Heuristic rules. They flag what real Mac malware relies on: disguised file types, broken or missing signatures,
/// Gatekeeper rejections, known adware names and hidden executables. Not a signature antivirus.
public enum ThreatRules {
    static let runnable: Set<FileKind> = [.app, .installerPackage, .executable, .script]
    static let decoyExtensions: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "jpg", "jpeg", "png", "mp4", "mov", "mp3", "txt", "zip"]

    public static func assess(_ facts: FileFacts) -> ThreatVerdict? {
        var reasons: [(FindingSeverity, String)] = []
        let name = facts.name
        let lower = name.lowercased()
        if runnable.contains(facts.kind), isDisguised(name) {
            reasons.append((.high, "Pretends to be a document (“\(name)”) but is a program"))
        }
        if let marker = SecurityAudit.knownAdwareMarkers.first(where: { lower.contains($0) }) {
            reasons.append((.high, "Matches known adware “\(marker)”"))
        }
        if case .rejected(let why) = facts.gatekeeper, facts.kind != .script {
            reasons.append((.high, "Gatekeeper rejects it: \(why)"))
        }
        switch (facts.kind, facts.signature) {
        case (.app, .invalid?), (.installerPackage, .invalid?), (.executable, .invalid?):
            reasons.append((.high, "Its code signature is broken: it may have been tampered with"))
        case (.app, .unsigned?), (.app, .missing?), (.installerPackage, .unsigned?):
            reasons.append((facts.isQuarantined ? .high : .medium, "Downloaded program with no developer signature"))
        case (.executable, .unsigned?) where facts.isQuarantined:
            reasons.append((.medium, "Downloaded command-line program with no signature"))
        default: break
        }
        if facts.kind == .script, facts.isQuarantined, FileKind.runOnOpenExtensions.contains((name as NSString).pathExtension.lowercased()) {
            reasons.append((.medium, "Downloaded script that runs commands when double-clicked"))
        }
        if name.hasPrefix("."), runnable.contains(facts.kind) {
            reasons.append((.high, "Hidden program file"))
        }
        guard let worst = reasons.map(\.0).max() else { return nil }
        return ThreatVerdict(facts: facts, severity: worst, reasons: reasons.map(\.1))
    }

    /// "invoice.pdf.app", "photo.jpg.command", or a long run of spaces before the real extension.
    static func isDisguised(_ name: String) -> Bool {
        let parts = name.lowercased().split(separator: ".")
        if parts.count >= 3, decoyExtensions.contains(String(parts[parts.count - 2])) { return true }
        return name.contains("     ")
    }
}
