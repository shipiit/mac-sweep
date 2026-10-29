import SwiftUI

struct AppearanceSettings: View {
    @Environment(\.appAccent) private var accentColor
    @AppStorage(SettingsKeys.theme) private var theme: ThemeChoice = .system
    @AppStorage(SettingsKeys.accent) private var accent: AccentChoice = .system
    @AppStorage(SettingsKeys.backgroundStyle) private var backgroundStyle: BackgroundStyle = .plain
    @AppStorage(SettingsKeys.backgroundHex) private var backgroundHex = ThemePreset.teal.hex
    @AppStorage(SettingsKeys.sidebarHex) private var sidebarHex = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AppearancePreview(sidebarHex: sidebarHex, backgroundStyle: backgroundStyle, backgroundHex: backgroundHex)
                section("Theme") {
                    HStack(spacing: 12) {
                        ForEach(ThemeChoice.allCases) { choice in
                            OptionCard(title: choice.rawValue, isSelected: theme == choice) { ThemeSwatch(choice: choice) } action: { theme = choice }
                        }
                    }
                }
                section("Accent colour") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                        ForEach(AccentChoice.allCases) { choice in
                            Button { accent = choice } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(choice.color.map { AnyShapeStyle($0) }
                                              ?? AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center)))
                                        .frame(width: 18, height: 18)
                                        .overlay { if accent == choice { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) } }
                                    Text(choice == .system ? "macOS" : choice.rawValue.capitalized).font(.callout)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(.quaternary.opacity(accent == choice ? 0.8 : 0.3), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(accent == choice ? accentColor : .clear, lineWidth: 1.5))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice == .system ? "macOS accent" : choice.rawValue)
                            .accessibilityAddTraits(accent == choice ? .isSelected : [])
                        }
                    }
                }
                section("Window background") {
                    HStack(spacing: 12) {
                        ForEach(BackgroundStyle.allCases) { style in
                            OptionCard(title: style.rawValue, isSelected: backgroundStyle == style) {
                                BackgroundSwatch(style: style, hex: backgroundHex)
                            } action: { backgroundStyle = style }
                        }
                    }
                    if backgroundStyle != .plain { ColorChoiceRow(title: "Background colour", hex: $backgroundHex) }
                }
                section("Sidebar") {
                    ColorChoiceRow(title: "Highlight colour", hex: $sidebarHex, allowsAccent: true)
                }
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        theme = .system
                        accent = .system
                        backgroundStyle = .plain
                        backgroundHex = ThemePreset.teal.hex
                        sidebarHex = ""
                        ThemeApplier.apply(ThemeChoice.system.rawValue)
                    }
                }
            }
            .padding(20)
        }
        .onChange(of: theme) { _, value in ThemeApplier.apply(value.rawValue) }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// Selectable card with a picture and a label; the selected one gets an accent border and a check.
private struct OptionCard<Picture: View>: View {
    let title: String
    let isSelected: Bool
    @ViewBuilder let picture: Picture
    let action: () -> Void
    @Environment(\.appAccent) private var accent

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                picture.frame(height: 56).frame(maxWidth: .infinity)
                HStack(spacing: 5) {
                    if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                    Text(title).font(.callout.weight(isSelected ? .semibold : .regular))
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isSelected ? accent : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BackgroundSwatch: View {
    let style: BackgroundStyle
    let hex: String

    var body: some View {
        let tint = Color(hex: hex) ?? .teal
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(style == .plain ? AnyShapeStyle(.background) : style == .tinted ? AnyShapeStyle(tint.opacity(0.18))
                  : AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.35), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

/// A miniature MacSweep window that reflects the current choices.
private struct AppearancePreview: View {
    let sidebarHex: String
    let backgroundStyle: BackgroundStyle
    let backgroundHex: String
    @Environment(\.appAccent) private var accent

    var body: some View {
        let highlight = Color(hex: sidebarHex) ?? accent
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) { ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 7, height: 7) } }
                    .padding(.bottom, 6)
                ForEach(0..<6) { index in
                    RoundedRectangle(cornerRadius: 4).fill(index == 1 ? highlight : Color.secondary.opacity(0.2)).frame(height: 10)
                }
                Spacer()
            }
            .padding(10)
            .frame(width: 110)
            .background(.quaternary.opacity(0.4))
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.6)).frame(width: 120, height: 10)
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.background)
                            .overlay(alignment: .topLeading) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Circle().fill(index == 0 ? accent : .secondary.opacity(0.4)).frame(width: 12, height: 12)
                                    RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.4)).frame(width: 40, height: 5)
                                    Capsule().fill(accent).frame(width: index == 0 ? 50 : 30, height: 5)
                                }
                                .padding(8)
                            }
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator.opacity(0.6)))
                    }
                }
                Capsule().fill(accent).frame(width: 90, height: 18).overlay(Text("Scan").font(.caption2.weight(.semibold)).foregroundStyle(.white))
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { BackgroundSwatch(style: backgroundStyle, hex: backgroundHex) }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
        .accessibilityHidden(true)
    }
}
