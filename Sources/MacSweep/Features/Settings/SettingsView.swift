import MacSweepCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            DashboardSettings().tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            SidebarSettings().tabItem { Label("Sidebar", systemImage: "sidebar.left") }
            AISettings().tabItem { Label("AI", systemImage: "flame") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
            ShortcutsSettings().tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 640, height: 520)
    }
}

private struct GeneralSettings: View {
    @AppStorage("scanSchedule") private var schedule: ScanSchedule = .nightly
    @AppStorage("showNotchHUD") private var showNotch = true
    @AppStorage(SettingsKeys.autoCleanWeekly) private var autoClean = false
    @AppStorage(SettingsKeys.liveDockIcon) private var liveDockIcon = true
    @AppStorage(SettingsKeys.menuBarStyle) private var menuBarStyle: MenuBarStyle = .cpuAndMemory
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open MacSweep at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Automatic cleanup") {
                Toggle("Clean safe junk every week", isOn: $autoClean)
                Text("Only items marked Safe to remove (caches, build output, update leftovers), never anything in use or marked Review first. They go to the Trash, and you get a notification with the amount.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Disk") {
                Picker("Automatic scan", selection: $schedule) {
                    ForEach(ScanSchedule.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("Scheduled scans run at low priority and are skipped on battery below 30%.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar, notch & Dock") {
                Picker("Menu bar shows", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Show live stats around the notch", isOn: $showNotch)
                Toggle("Live CPU & memory in the Dock icon", isOn: $liveDockIcon)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change: \(error.localizedDescription). Install MacSweep in /Applications first."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct ThemeSwatch: View {
    @Environment(\.appAccent) private var accent
    let choice: ThemeChoice

    var body: some View {
        HStack(spacing: 0) {
            if choice != .dark { panel(light: true) }
            if choice != .light { panel(light: false) }
        }
        .frame(width: 96, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func panel(light: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            (light ? Color(white: 0.95) : Color(white: 0.15))
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(accent).frame(width: 30, height: 5)
                Capsule().fill(light ? Color(white: 0.8) : Color(white: 0.35)).frame(width: 22, height: 4)
            }
            .padding(8)
        }
    }
}

private struct DashboardSettings: View {
    @AppStorage(SettingsKeys.dashboardCards) private var raw = ""

    var body: some View {
        let visible = DashboardLayout.decode(raw)
        let hidden = DashboardCardKind.allCases.filter { !visible.contains($0) }
        Form {
            Section("Shown (drag to reorder)") {
                List {
                    ForEach(visible) { card in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).accessibilityHidden(true)
                            Text(card.rawValue)
                            Spacer()
                            Button("Hide") { raw = DashboardLayout.encode(visible.filter { $0 != card }) }
                        }
                    }
                    .onMove { from, to in
                        var cards = visible
                        cards.move(fromOffsets: from, toOffset: to)
                        raw = DashboardLayout.encode(cards)
                    }
                }
                .frame(minHeight: 200)
            }
            if !hidden.isEmpty {
                Section("Hidden") {
                    ForEach(hidden) { card in
                        HStack {
                            Text(card.rawValue).foregroundStyle(.secondary)
                            Spacer()
                            Button("Show") { raw = DashboardLayout.encode(visible + [card]) }
                        }
                    }
                }
            }
            Button("Reset to Default") { raw = "" }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKeys.trackUsage) private var trackUsage = true
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("App usage") {
                Toggle("Track time spent in each app", isOn: $trackUsage)
                    .onChange(of: trackUsage) { _, enabled in enabled ? app.usage.start() : app.usage.stop() }
                Text("Stored only on this Mac in ~/Library/Application Support/MacSweep. Kept for 30 days. Never sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Clear Usage History…", role: .destructive) { confirmClear = true }
            }
            Section("Data MacSweep keeps") {
                Text("The last disk scan and app usage history. Nothing is uploaded; MacSweep makes no network requests except the speed test and update checks you start.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Show in Finder") {
                    FileActions.reveal(NSHomeDirectory() + "/Library/Application Support/MacSweep")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all recorded app usage?", isPresented: $confirmClear) {
            Button("Delete", role: .destructive) { app.usage.clear() }
        }
    }
}

private struct ShortcutsSettings: View {
    private let shortcuts: [(String, String)] = [
        ("⌘1 – ⌘9", "Jump to a section (Go menu)"), ("⌘R", "Rescan / refresh the current page"),
        ("⌘↑", "Up one folder in the disk map"), ("⌘⌫", "Clean selected items / quit selected process"),
        ("⌘F", "Search the current list"), ("⌘,", "Settings"), ("⌘Q", "Quit MacSweep"),
    ]

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                ForEach(shortcuts, id: \.0) { key, action in
                    HStack {
                        Text(key).font(.system(.body, design: .monospaced)).frame(width: 110, alignment: .leading)
                        Text(action).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
