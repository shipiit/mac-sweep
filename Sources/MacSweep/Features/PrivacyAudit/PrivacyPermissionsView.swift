import MacSweepCore
import SwiftUI

/// Which apps can use the camera, microphone, screen, files and input, read from TCC.db (read-only).
struct PrivacyPermissionsView: View {
    @State private var model = PrivacyPermissionsModel.shared

    var body: some View {
        Group {
            if model.phase == .idle || (model.phase == .loading && model.entries.isEmpty) {
                ProgressView("Reading privacy permissions…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .navigationTitle("App Permissions")
        .toolbar {
            ToolbarItem {
                Button { Task { await model.load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.phase == .loading)
            }
        }
        .task { if model.phase == .idle { await model.load() } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StatStrip {
                    StatTile(title: "Powerful access", value: Format.count(model.powerfulClientCount),
                             detail: "apps can watch or control")
                    StatTile(title: "Flagged", value: Format.count(model.riskyClientCount),
                             detail: model.riskyClientCount == 0 ? "nothing risky" : "need a look",
                             dot: model.riskyClientCount == 0 ? nil : .orange)
                    StatTile(title: "Grants", value: Format.count(model.grantedCount),
                             detail: needsAccess ? "Full Disk Access needed" : "allowed in total")
                }
                banner
                if model.phase == .loaded || (model.phase == .loading && !model.entries.isEmpty) {
                    Toggle("Show Apple system services", isOn: $model.showsAppleClients).toggleStyle(.checkbox)
                    groups
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private var needsAccess: Bool { model.phase == .needsFullDiskAccess || model.isPartial }

    @ViewBuilder private var banner: some View {
        switch model.phase {
        case .needsFullDiskAccess:
            NoticeBanner(symbol: "lock.shield", title: "Full Disk Access is needed",
                         message: "macOS keeps the list of app permissions in a protected database. Give MacSweep Full Disk Access to read it; MacSweep never changes it.",
                         actionTitle: "Open Full Disk Access") { FileActions.open(url: Permissions.fullDiskAccessSettingsURL) }
        case .failed(let message):
            NoticeBanner(symbol: "exclamationmark.triangle", title: "Couldn't read permissions", message: message,
                         actionTitle: "Try Again") { Task { await model.load() } }
        case .loaded where model.isPartial:
            NoticeBanner(symbol: "lock.shield", title: "Some permissions are hidden",
                         message: "System-wide grants such as Screen Recording and Full Disk Access need Full Disk Access to read.",
                         actionTitle: "Open Full Disk Access") { FileActions.open(url: Permissions.fullDiskAccessSettingsURL) }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var groups: some View {
        let groups = model.groups
        if groups.isEmpty {
            Card {
                Label("No apps have asked for privacy permissions.", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(groups) { group in
                PermissionServiceCard(group: group, model: model)
            }
        }
    }
}

extension PrivacyPermissionsModel {
    /// One instance for the app's lifetime, so results stay when you switch pages; Rescan refreshes them.
    static let shared = PrivacyPermissionsModel()
}
