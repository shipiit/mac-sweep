import Foundation
import MacSweepCore

/// One "x% left" line for compact surfaces (menu bar tile, notch).
struct AILimitLine: Identifiable, Equatable {
    let title: String
    /// Fraction remaining, 0...1.
    let left: Double
    let resetsAt: Date?
    var id: String { title }
}

extension AIUsageModel {
    /// The tool chosen in Settings for the menu bar and notch (Claude Code unless changed).
    static var defaultTool: AIProvider {
        UserDefaults.standard.string(forKey: SettingsKeys.aiDefaultTool).flatMap(AIProvider.init(rawValue:)) ?? .claudeCode
    }

    /// Session first, then weekly. Claude uses real plan limits when enabled, else the 5-hour block's time left.
    func limitLines(for provider: AIProvider, now: Date = Date()) -> [AILimitLine] {
        switch provider {
        case .claudeCode:
            if let plan = planUsage {
                return [plan.session, plan.weekly].compactMap { $0 }
                    .map { AILimitLine(title: "Claude " + ($0.name == "Session" ? "5h" : "week"), left: Double($0.percentLeft) / 100, resetsAt: $0.resetsAt) }
            }
            guard let block = claudeBlock, block.isActive else {
                return [AILimitLine(title: "Claude 5h", left: 1, resetsAt: nil)]
            }
            let left = 1 - min(max(now.timeIntervalSince(block.start) / (5 * 3_600), 0), 1)
            return [AILimitLine(title: "Claude 5h", left: left, resetsAt: block.end)]
        case .codex:
            return [("Codex 5h", codexLimits?.primary), ("Codex week", codexLimits?.secondary)].compactMap { title, window in
                window.map { AILimitLine(title: title, left: 1 - $0.usedFraction(now: now), resetsAt: $0.hasReset(now: now) ? nil : $0.resetsAt) }
            }
        }
    }
}
