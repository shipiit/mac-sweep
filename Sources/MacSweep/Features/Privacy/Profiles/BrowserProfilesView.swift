import MacSweepCore
import SwiftUI

/// Privacy tab: every Chromium profile with a size breakdown and a per-profile cache clean.
struct BrowserProfilesView: View {
    @State private var model = BrowserProfilesModel.shared
    @State private var pendingClean: BrowserProfile?
    @Environment(\.appAccent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StatStrip {
                    StatTile(title: "Profiles", value: Format.count(model.profileCount))
                    StatTile(title: "Total size", value: Format.bytes(model.totalSize))
                    StatTile(title: "Safe to clean", value: Format.bytes(model.cleanableSize), detail: "Caches only")
                }
                if let message = model.message {
                    NoticeBanner(symbol: "info.circle", title: "Browser profiles", message: message, tint: accent,
                                 actionTitle: "Dismiss") { model.message = nil }
                }
                content
            }
            .padding(20)
        }
        .task { if !model.hasLoaded { await model.refresh() } }
        .confirmationDialog(confirmTitle, isPresented: isConfirming, presenting: pendingClean) { profile in
            Button("Move Caches to Trash") { Task { await model.cleanCaches(profile) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Only caches are removed. You stay signed in, and the browser rebuilds them as you browse.")
        }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading && !model.hasLoaded {
            Card { HStack { ProgressView().controlSize(.small); Text("Measuring browser profiles…").foregroundStyle(.secondary) } }
        } else if model.groups.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "No Chromium browsers found",
                                  subtitle: "Chrome, Brave, Edge, Arc and Vivaldi profiles appear here once those browsers have been used.")
                    Button("Scan Again", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                }
            }
        } else {
            HStack {
                SectionHeader(title: "Browser profiles", subtitle: "Caches are safe to clean. Site data is shown for review only.")
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .disabled(model.isLoading)
            }
            ForEach(model.groups) { group in
                BrowserGroupCard(group: group, cleaning: model.cleaning, blockedReason: model.blockedReason(for: group.browser)) {
                    pendingClean = $0
                }
            }
        }
    }

    private var confirmTitle: String {
        pendingClean.map { "Clean \(Format.bytes($0.size(of: .safe))) of caches from \($0.browser.name) · \($0.displayName)?" } ?? ""
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { pendingClean != nil }, set: { if !$0 { pendingClean = nil } })
    }
}

extension BrowserProfilesModel {
    /// One instance for the app's lifetime, so results stay when you switch pages; Rescan refreshes them.
    static let shared = BrowserProfilesModel()
}
