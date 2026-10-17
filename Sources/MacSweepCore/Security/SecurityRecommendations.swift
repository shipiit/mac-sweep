import Foundation

/// What to do next, from the audit's own results, most important first.
public struct SecurityRecommendation: Identifiable, Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case enableFirewall
        case openSettings(String)
        case reviewExtensions
        case reviewFindings
        case enableDownloadProtection
    }

    public let id: String
    public let severity: FindingSeverity
    public let title: String
    public let detail: String
    public let actionTitle: String
    public let action: Action
}

public enum SecurityAdvisor {
    public static func recommendations(protections: [ProtectionCheck], findings: Int, highRiskExtensions: Int,
                                       downloadProtection: Bool) -> [SecurityRecommendation] {
        var list: [SecurityRecommendation] = []
        for check in protections where check.state == .off {
            switch check.id {
            case "firewall":
                list.append(.init(id: "firewall", severity: .high, title: "Turn on the Firewall", detail: "Blocks unwanted incoming connections to your Mac.",
                                  actionTitle: "Turn On", action: .enableFirewall))
            case "filevault":
                list.append(.init(id: "filevault", severity: .high, title: "Turn on FileVault", detail: "Encrypts your disk so a lost Mac can't be read.",
                                  actionTitle: "Open Settings", action: .openSettings(check.settingsURL ?? "")))
            default:
                list.append(.init(id: check.id, severity: .high, title: "Turn on \(check.title)", detail: check.detail,
                                  actionTitle: "Open Settings", action: .openSettings(check.settingsURL ?? "")))
            }
        }
        if findings > 0 {
            list.append(.init(id: "findings", severity: .high, title: "Review \(findings) suspicious item\(findings == 1 ? "" : "s")",
                              detail: "Startup items or programs that look risky.", actionTitle: "Review", action: .reviewFindings))
        }
        if highRiskExtensions > 0 {
            list.append(.init(id: "extensions", severity: .medium, title: "Review high-risk browser extensions",
                              detail: "\(highRiskExtensions) extension\(highRiskExtensions == 1 ? "" : "s") can read sensitive data.",
                              actionTitle: "Review", action: .reviewExtensions))
        }
        if !downloadProtection {
            list.append(.init(id: "downloads", severity: .medium, title: "Turn on Download Protection",
                              detail: "Checks every download and quarantines clear threats.", actionTitle: "Turn On", action: .enableDownloadProtection))
        }
        return list.sorted { $0.severity > $1.severity }
    }

    /// Short status for the sidebar badge: nil until the first audit has run.
    public static func badge(hasRun: Bool, protectionsOff: Int, findings: Int) -> String? {
        guard hasRun else { return nil }
        let issues = protectionsOff + findings
        return issues == 0 ? "Secure" : "\(issues) issue\(issues == 1 ? "" : "s")"
    }
}
