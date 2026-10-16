import AppKit
import MacSweepCore
import SwiftUI

/// Apps that open when you log in, plus (on request) everything macOS lets run in the background.
struct LoginItemsView: View {
    @State private var items: [LoginItem]?
    @State private var background: [BackgroundItem]?
    @State private var loadingBackground = false
    @State private var error: String?
    @State private var pendingRemoval: LoginItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader(title: "Open at login", subtitle: "These apps start every time you log in")
                            Spacer()
                            Button("Add App…", systemImage: "plus") { addApp() }
                        }
                        if let items {
                            if items.isEmpty { Text("No apps open at login.").foregroundStyle(.secondary) }
                            ForEach(items) { item in
                                HStack(spacing: 12) {
                                    FileIcon(path: item.path, size: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).fontWeight(.medium)
                                        Text(Format.path(item.path)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                    if item.hidden { Pill(text: "Opens hidden") }
                                    Spacer()
                                    Button("Reveal") { FileActions.reveal(item.path) }
                                    Button("Remove…", role: .destructive) { pendingRemoval = item }
                                }
                                .controlSize(.small)
                                .padding(.vertical, 4)
                            }
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader(title: "All background items",
                                          subtitle: "Everything macOS allows to run in the background, with its developer. Needs your password to read.")
                            Spacer()
                            Button(background == nil ? "Show All…" : "Refresh", systemImage: "lock") { Task { await loadBackground() } }
                                .disabled(loadingBackground)
                        }
                        if loadingBackground { ProgressView().controlSize(.small) }
                        if let background {
                            ForEach(background) { item in
                                HStack(spacing: 12) {
                                    Image(systemName: item.enabled ? "checkmark.circle.fill" : "minus.circle")
                                        .foregroundStyle(item.enabled ? .green : .secondary)
                                        .accessibilityLabel(item.enabled ? "Enabled" : "Disabled")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).fontWeight(.medium)
                                        Text([item.developer, item.type, item.identifier].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if let url = item.url, let path = URL(string: url)?.path, !path.isEmpty {
                                        Button("Reveal") { FileActions.reveal(path) }.controlSize(.small)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                            Button("Manage in System Settings") { FileActions.open(url: Permissions.loginItemsSettingsURL) }
                                .buttonStyle(.link)
                        }
                    }
                }
            }
            .padding(20)
        }
        .task { await load() }
        .confirmationDialog("Stop \(pendingRemoval?.name ?? "") opening at login?", isPresented: isPresented($pendingRemoval), titleVisibility: .visible,
                            presenting: pendingRemoval) { item in
            Button("Remove from Login Items", role: .destructive) { Task { await remove(item) } }
        } message: { _ in Text("The app stays installed; it just won't start automatically.") }
        .alert("Login items", isPresented: isPresented($error), presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0) }
    }

    private func load() async {
        do { items = try await LoginItems.list() } catch {
            items = []
            self.error = "MacSweep needs permission to read login items. Allow it under System Settings › Privacy & Security › Automation."
        }
    }

    private func loadBackground() async {
        loadingBackground = true
        defer { loadingBackground = false }
        do { background = try await LoginItems.backgroundItems() } catch AdminRunner.AdminError.cancelled { return } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ item: LoginItem) async {
        do { try await LoginItems.remove(item) } catch { self.error = error.localizedDescription }
        await load()
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Open at Login"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await LoginItems.add(appPath: url.path) } catch { self.error = error.localizedDescription }
            await load()
        }
    }
}
