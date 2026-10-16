import Foundation

/// What MacSweep could find out about the app behind a TCC client.
public struct TCCClientInfo: Sendable, Equatable {
    public let name: String
    /// The app bundle or executable on disk; nil when no installed app matches the bundle ID.
    public let path: String?
    public let signature: SignatureStatus?

    public init(name: String, path: String?, signature: SignatureStatus?) {
        self.name = name
        self.path = path
        self.signature = signature
    }

    /// Readable fallback when the app can't be located: the last bundle ID component or file name.
    public static func unresolved(_ client: TCCEntry.Client) -> TCCClientInfo {
        let name: String
        switch client {
        case .bundleID(let id): name = id.split(separator: ".").last.map(String.init) ?? id
        case .path(let path): name = (path as NSString).lastPathComponent
        }
        return TCCClientInfo(name: name, path: nil, signature: nil)
    }
}

public struct TCCRiskFlag: Sendable, Equatable {
    public let severity: FindingSeverity
    public let reason: String
}

public struct TCCServiceGroup: Identifiable, Sendable, Equatable {
    public let service: TCCService
    public let entries: [TCCEntry]

    public var id: String { service.key }
    public var allowedCount: Int { entries.filter { $0.authorization.isGranted }.count }
}

public enum TCCRisk {
    /// Flags powerful grants held by code that can't be traced to a trusted developer. Denied grants never count.
    public static func assess(_ entry: TCCEntry, client: TCCClientInfo) -> TCCRiskFlag? {
        guard entry.authorization.isGranted, entry.service.isPowerful else { return nil }
        let service = entry.service.title
        if let path = client.path ?? clientPath(entry.client),
           SecurityAudit.suspiciousLocations.contains(where: path.lowercased().contains) {
            return TCCRiskFlag(severity: .high, reason: "Runs from a temporary or download folder and has \(service)")
        }
        switch client.signature {
        case .none:
            return TCCRiskFlag(severity: .medium, reason: "Unknown app (couldn't be found on this Mac) has \(service)")
        case .unsigned?, .invalid?:
            return TCCRiskFlag(severity: .high, reason: "Unsigned or tampered code has \(service)")
        case .adHoc?:
            return TCCRiskFlag(severity: .medium, reason: "Ad-hoc signed code (no identified developer) has \(service)")
        case .missing?:
            return TCCRiskFlag(severity: .low, reason: "Leftover \(service) grant for an app that's gone")
        case .apple?, .developer?:
            return nil
        }
    }

    /// Groups entries per service in catalog order, unknown internal services last; allowed before denied.
    public static func group(_ entries: [TCCEntry]) -> [TCCServiceGroup] {
        Dictionary(grouping: entries, by: \.serviceKey)
            .map { key, items in
                TCCServiceGroup(service: items.first?.service ?? TCCServiceCatalog.fallback(for: key),
                                entries: items.sorted { ($0.authorization.isGranted ? 0 : 1, $0.client.raw) < ($1.authorization.isGranted ? 0 : 1, $1.client.raw) })
            }
            .sorted { (TCCServiceCatalog.order(of: $0.service.key), $0.service.title) < (TCCServiceCatalog.order(of: $1.service.key), $1.service.title) }
    }

    /// Apple's own daemons hold many grants; they're system plumbing, not something a user reviews.
    public static func isAppleSystemClient(_ client: TCCEntry.Client) -> Bool {
        switch client {
        case .bundleID(let id): id.hasPrefix("com.apple.")
        case .path(let path): path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/") || path.hasPrefix("/usr/bin/")
        }
    }

    static func clientPath(_ client: TCCEntry.Client) -> String? {
        if case .path(let path) = client { return path }
        return nil
    }
}
