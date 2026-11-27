import Foundation

/// A pending update with how much it matters for security.
public struct SecurityPatch: Sendable, Equatable, Identifiable {
    public let update: AvailableUpdate
    public let severity: FindingSeverity
    public let reason: String
    public var id: String { update.id }
}

/// Apple's built-in malware definitions: which version is installed and when it last changed.
public struct MalwareDefinitions: Sendable, Equatable {
    public let version: String
    public let updated: Date?
}

/// Ranks pending updates by security impact, so the ones that close holes come first.
public enum SecurityPatches {
    /// Tools that talk to the network or handle keys: an old version of one of these is a real exposure.
    static let sensitiveTools: Set<String> = [
        "openssl", "curl", "wget", "git", "openssh", "gnupg", "gnutls", "ca-certificates", "node", "python", "ruby", "go", "nginx",
        "postgresql", "mysql", "redis", "sqlite", "libxml2", "libssh2", "nghttp2", "docker", "tailscale", "nmap", "sudo", "rsync",
    ]

    static func baseName(_ name: String) -> String {
        String(name.split(separator: "@").first ?? Substring(name)).lowercased()
    }

    public static func rank(_ update: AvailableUpdate) -> SecurityPatch {
        switch update.source {
        case .macOS:
            let name = update.name.lowercased()
            if name.hasPrefix("macos") || name.contains("security") || name.contains("safari") {
                return SecurityPatch(update: update, severity: .high, reason: "Apple ships its security fixes in these. Install it soon.")
            }
            return SecurityPatch(update: update, severity: .medium, reason: "An Apple system component.")
        case .homebrewCask:
            return SecurityPatch(update: update, severity: .medium, reason: "An app that is behind its latest version.")
        case .homebrewFormula:
            return sensitiveTools.contains(baseName(update.name))
                ? SecurityPatch(update: update, severity: .medium, reason: "Handles network traffic or keys, so old versions are a common way in.")
                : SecurityPatch(update: update, severity: .low, reason: "A developer tool that is behind its latest version.")
        }
    }

    /// Most important first; ties keep their name order.
    public static func ranked(_ updates: [AvailableUpdate]) -> [SecurityPatch] {
        updates.map(rank).sorted { ($0.severity.rawValue, $1.update.name) > ($1.severity.rawValue, $0.update.name) }
    }

    public static func malwareDefinitions(paths: [String] = [
        "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist",
        "/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist",
    ]) -> MalwareDefinitions? {
        for path in paths {
            guard let plist = NSDictionary(contentsOfFile: path), let version = plist["CFBundleShortVersionString"] as? String else { continue }
            let updated = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            return MalwareDefinitions(version: version, updated: updated)
        }
        return nil
    }
}
