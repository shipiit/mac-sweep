import Foundation

/// One-word health verdict for the Smart Scan home, from things MacSweep actually measured.
public enum MacHealth: String, Sendable, Equatable {
    case excellent = "Excellent", veryGood = "Very Good", good = "Good", needsAttention = "Needs Attention"

    /// - securityScore: 0...100 from the security audit. tips: advisor suggestions. freeFraction: free disk space 0...1.
    public static func grade(securityScore: Int, highFindings: Int, tips: Int, freeFraction: Double) -> MacHealth {
        if highFindings > 0 || securityScore < 60 || freeFraction < 0.05 { return .needsAttention }
        var points = 0
        points += securityScore >= 90 ? 2 : securityScore >= 75 ? 1 : 0
        points += tips == 0 ? 2 : tips <= 3 ? 1 : 0
        points += freeFraction >= 0.25 ? 2 : freeFraction >= 0.15 ? 1 : 0
        switch points {
        case 6: return .excellent
        case 4...5: return .veryGood
        case 2...3: return .good
        default: return .needsAttention
        }
    }

    public var summary: String {
        switch self {
        case .excellent: "Everything checks out"
        case .veryGood: "No critical issues found"
        case .good: "A few things could be better"
        case .needsAttention: "Some issues need a look"
        }
    }
}
