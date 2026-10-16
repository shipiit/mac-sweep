import AppKit
import SwiftUI

@main
struct MacSweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("MacSweep", id: "main") {
            RootView()
                .environment(delegate.model)
        }
        .defaultSize(width: 1360, height: 880)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Go") {
                ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                    if index < 9 {
                        Button(section.rawValue) { delegate.model.section = section }
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    } else {
                        Button(section.rawValue) { delegate.model.section = section }
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(delegate.model)
                .appAccent()
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(delegate.model)
                .appAccent()
        } label: {
            MenuBarLabel(app: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var notch: NotchController?
    private var dockTile: DockTileController?
    private var autoQuitter: AutoQuitter?
    private var defaultsObserver: NSObjectProtocol?

    /// Keep running in the menu bar and notch after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        UserDefaults.standard.register(defaults: ["showNotchHUD": true, SettingsKeys.trackUsage: true, SettingsKeys.liveDockIcon: true])
        ThemeApplier.apply(UserDefaults.standard.string(forKey: SettingsKeys.theme) ?? ThemeChoice.system.rawValue)
        let notch = NotchController(app: model)
        self.notch = notch
        notch.setVisible(UserDefaults.standard.bool(forKey: "showNotchHUD"))
        let autoQuitter = AutoQuitter(app: model)
        self.autoQuitter = autoQuitter
        autoQuitter.start()
        let dockTile = DockTileController(app: model)
        self.dockTile = dockTile
        dockTile.setEnabled(UserDefaults.standard.bool(forKey: SettingsKeys.liveDockIcon))
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notch?.setVisible(UserDefaults.standard.bool(forKey: "showNotchHUD"))
                self?.dockTile?.setEnabled(UserDefaults.standard.bool(forKey: SettingsKeys.liveDockIcon))
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model.openMainWindow?() }
        return true
    }
}
