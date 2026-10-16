import SwiftUI

private struct AppAccentKey: EnvironmentKey {
    static let defaultValue = Color.accentColor
}

extension EnvironmentValues {
    /// The accent chosen in Settings (or the macOS accent when set to System). Use this instead of
    /// `Color.accentColor`, which always reflects the system setting and ignores the app's choice.
    var appAccent: Color {
        get { self[AppAccentKey.self] }
        set { self[AppAccentKey.self] = newValue }
    }
}

/// Applies the Settings accent to a whole scene: controls via `.tint`, custom drawing via `appAccent`.
struct AppAccentModifier: ViewModifier {
    @AppStorage(SettingsKeys.accent) private var accent: AccentChoice = .system

    func body(content: Content) -> some View {
        let color = accent.color ?? .accentColor
        content
            .tint(color)
            .environment(\.appAccent, color)
    }
}

extension View {
    func appAccent() -> some View { modifier(AppAccentModifier()) }
}
