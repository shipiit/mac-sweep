import AppKit
import SwiftUI

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case plain = "Plain"
    case tinted = "Tinted"
    case gradient = "Gradient"

    var id: String { rawValue }
}

/// Preset colours offered next to the custom colour picker. Stored as hex so any colour round-trips.
enum ThemePreset: String, CaseIterable, Identifiable {
    case teal, blue, indigo, purple, pink, red, orange, green, graphite

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .teal: "#0FB5A0"
        case .blue: "#2F7CF6"
        case .indigo: "#5856D6"
        case .purple: "#9B51E0"
        case .pink: "#E8457C"
        case .red: "#E5484D"
        case .orange: "#F5871F"
        case .green: "#34C759"
        case .graphite: "#8E8E93"
        }
    }
}

extension SettingsKeys {
    static let backgroundStyle = "backgroundStyle"
    static let backgroundHex = "backgroundHex"
    /// Empty means "use the accent colour".
    static let sidebarHex = "sidebarHex"
}

extension Color {
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Window background driven by Settings › Appearance. Plain by default; Tinted is a single solid wash;
/// Gradient is the optional CleanMyMac-style look.
struct AppBackground: View {
    @AppStorage(SettingsKeys.backgroundStyle) private var style: BackgroundStyle = .plain
    @AppStorage(SettingsKeys.backgroundHex) private var hex = ThemePreset.teal.hex
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = Color(hex: hex) ?? .teal
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            switch style {
            case .plain:
                EmptyView()
            case .tinted:
                color.opacity(scheme == .dark ? 0.16 : 0.10)
            case .gradient:
                LinearGradient(colors: [color.opacity(scheme == .dark ? 0.55 : 0.35), Color.indigo.opacity(scheme == .dark ? 0.45 : 0.25)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}

/// Swatch row + custom colour well that writes a hex string.
struct ColorChoiceRow: View {
    let title: String
    @Binding var hex: String
    var allowsAccent = false
    /// The colour wheel fires continuously while dragging; only commit once the user pauses,
    /// otherwise every drag step re-themes and re-lays out every window.
    @State private var pending: Color?
    @State private var commit: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer()
            if allowsAccent {
                swatch(isSelected: hex.isEmpty, fill: AnyShapeStyle(Color.accentColor), label: "Same as accent") { hex = "" }
            }
            ForEach(ThemePreset.allCases) { preset in
                swatch(isSelected: hex == preset.hex, fill: AnyShapeStyle(Color(hex: preset.hex) ?? .gray), label: preset.rawValue.capitalized) {
                    hex = preset.hex
                }
            }
            ColorPicker("Custom \(title.lowercased())", selection: Binding(
                get: { pending ?? Color(hex: hex) ?? .accentColor },
                set: { color in
                    pending = color
                    commit?.cancel()
                    commit = Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        hex = color.hexString ?? hex
                        pending = nil
                    }
                }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }

    private func swatch(isSelected: Bool, fill: AnyShapeStyle, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(fill).frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.white, lineWidth: isSelected ? 2.5 : 0))
                .shadow(radius: isSelected ? 2 : 0)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
