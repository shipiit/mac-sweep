import AppKit
import MacSweepCore
import SwiftUI

extension PrivacyItem.Kind {
    var symbol: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .cookies: "key.horizontal"
        case .cache: "internaldrive"
        case .sessions: "square.on.square"
        case .recents: "doc.badge.clock"
        }
    }
}

struct PrivacyView: View {
    @Environment(AppModel.self) private var app
    @State private var confirm = false


    var body: some View {
        @Bindable var model = app.privacy
        let byApp = Dictionary(grouping: model.items, by: \.app)
        let selectedItems = model.items.filter { model.selected.contains($0.id) }
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary(items: model.items, apps: byApp.count)
                    if model.items.isEmpty {
                        ContentUnavailableView(model.isLoading ? "Looking for traces…" : "Nothing to clear", systemImage: "hand.raised")
                    }
                    EqualHeightGrid(items: byApp.keys.sorted().map { BrowserGroup(name: $0, items: byApp[$0] ?? []) }) { group in
                        BrowserPrivacyCard(name: group.name, items: group.items, model: model)
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Label("Passwords, autofill and bookmarks are never touched.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(selectedItems.isEmpty ? "Nothing selected"
                     : "\(selectedItems.count) selected · \(Format.bytes(selectedItems.reduce(0) { $0 + $1.size }))")
                    .monospacedDigit().foregroundStyle(.secondary)
                Button("Clear…") { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedItems.isEmpty)
            }
            .padding(14)
            .background(.bar)
        }
        .navigationTitle("Privacy")
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
        }
        .confirmationDialog("Permanently clear \(selectedItems.count) items?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { Task { await model.clearSelected() } }
        } message: {
            Text(selectedItems.map { "\($0.app): \($0.kind.rawValue)" }.joined(separator: "\n")
                 + "\n\nThis skips the Trash. Clearing cookies signs you out of websites.")
        }
        .alert(model.message ?? "", isPresented: isPresented($model.message)) { Button("OK", role: .cancel) {} }
        .task { await model.refresh() }
    }

    private func summary(items: [PrivacyItem], apps: Int) -> some View {
        let total = items.reduce(0) { $0 + $1.size }
        let running = app.privacy.runningApps(for: items)
        return Card(padding: 18) {
            HStack(spacing: 16) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 30)).foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Format.bytes(total)) of browsing traces in \(apps) apps").font(.title2.weight(.semibold))
                    Text("History, cookies, open-tab sessions and caches. Pick what to clear; nothing is selected for you.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !running.isEmpty {
                    Label("\(running.joined(separator: ", ")) open. Quit before clearing", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        }
    }
}

private struct BrowserPrivacyCard: View {
    @Environment(\.appAccent) private var accent
    let name: String
    let items: [PrivacyItem]
    let model: PrivacyModel

    var body: some View {
        let ids = Set(items.map(\.id))
        let allSelected = ids.isSubset(of: model.selected)
        let bundleID = items.first?.bundleID
        let isRunning = !model.runningApps(for: items).isEmpty
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    FileIcon(path: url.path, size: 30)
                } else {
                    Image(systemName: "macwindow").font(.title2).frame(width: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.headline)
                    Text(Format.bytes(items.reduce(0) { $0 + $1.size })).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if isRunning, let bundleID {
                    Pill(text: "Open", color: .orange)
                    Button("Quit") {
                        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
                        Task { try? await Task.sleep(for: .seconds(1)); await model.refresh() }
                    }
                    .controlSize(.small)
                }
                Button(allSelected ? "Deselect" : "Select All") {
                    if allSelected { model.selected.subtract(ids) } else { model.selected.formUnion(ids) }
                }
                .controlSize(.small)
            }
            Divider()
            ForEach(items) { item in
                Toggle(isOn: Binding(get: { model.selected.contains(item.id) },
                                     set: { if $0 { model.selected.insert(item.id) } else { model.selected.remove(item.id) } })) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.kind.symbol).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.kind.rawValue).fontWeight(.medium)
                            Text(item.consequence).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(ids.isDisjoint(with: model.selected) ? Color(nsColor: .separatorColor).opacity(0.5) : accent.opacity(0.6)))
    }
}

private struct BrowserGroup: Identifiable {
    let name: String
    let items: [PrivacyItem]

    var id: String { name }
}
