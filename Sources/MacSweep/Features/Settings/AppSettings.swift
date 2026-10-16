import AppKit
import SwiftUI

enum ThemeChoice: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite

    var id: String { rawValue }

    /// Nil means "follow the macOS accent colour".
    var color: Color? {
        switch self {
        case .system: nil
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .graphite: .gray
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case cpuAndMemory = "CPU & memory"
    case cpuOnly = "CPU only"
    case iconOnly = "Icon only"

    var id: String { rawValue }
}

/// Dashboard tiles the user can show, hide and reorder.
enum DashboardCardKind: String, CaseIterable, Identifiable, Codable {
    case activity = "Activity chart"
    case storage = "Storage"
    case memory = "Memory"
    case battery = "Battery"
    case network = "Network"
    case security = "Security"
    case devices = "Connected devices"
    case topMemory = "Top memory"
    case topCPU = "Top CPU"
    case ports = "Listening ports"
    case usage = "App usage today"

    var id: String { rawValue }
}

enum SettingsKeys {
    static let theme = "theme"
    static let accent = "accent"
    static let menuBarStyle = "menuBarStyle"
    static let trackUsage = "trackUsage"
    static let dashboardCards = "dashboardCards"
    /// Opt-in: read Claude Code's sign-in to show real Claude plan limits.
    static let claudePlanLimits = "claudePlanLimits"
    /// Which tool's limits the menu bar tile and notch show.
    static let aiDefaultTool = "aiDefaultTool"
}

enum DashboardLayout {
    /// Stored as a comma-separated list of visible cards in display order.
    static func decode(_ raw: String) -> [DashboardCardKind] {
        guard !raw.isEmpty else { return DashboardCardKind.allCases }
        return raw.split(separator: ",").compactMap { DashboardCardKind(rawValue: String($0)) }
    }

    static func encode(_ cards: [DashboardCardKind]) -> String {
        cards.map(\.rawValue).joined(separator: ",")
    }
}

/// Applies the chosen theme app-wide (main window, menu bar panel and notch alike).
@MainActor
enum ThemeApplier {
    static func apply(_ rawValue: String) {
        NSApp.appearance = (ThemeChoice(rawValue: rawValue) ?? .system).appearance
    }
}
