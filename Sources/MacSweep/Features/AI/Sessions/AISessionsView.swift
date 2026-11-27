import MacSweepCore
import SwiftUI

/// Every Claude Code and Codex session: project, age, size and name, so old ones can be reviewed and removed.
struct AISessionsView: View {
    @State private var model = AISessionsModel.shared
    @State private var search = ""
    @State private var provider: AIProvider?
    @State private var minimumAge = 0
    @State private var confirming = false
    @State private var confirmingSlim = false
    @State private var confirmingCompress = false
    @State private var limit = 100
    @Environment(\.appAccent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StatStrip {
                    StatTile(title: "Sessions", value: Format.count(model.sessions.count))
                    StatTile(title: "On disk", value: Format.bytes(model.totalSize), detail: "transcripts, subagents & file history")
                    StatTile(title: "Slimmable", value: Format.bytes(model.extrasSize), detail: "extras, conversations kept", dot: model.extrasSize > 0 ? .green : nil)
                    StatTile(title: "Older than 30 days", value: Format.bytes(oldSize(30)), detail: "named sessions excluded")
                    StatTile(title: "Selected", value: Format.bytes(model.selectedSize), detail: "\(model.selected.count) sessions")
                }
                if let report = model.report {
                    NoticeBanner(symbol: "checkmark.circle", title: "Done", message: report, tint: .green, actionTitle: "Dismiss") { model.report = nil }
                }
                controls
                if !model.archived.isEmpty { ArchivedSessionsCard(model: model) }
                list
            }
            .padding(20)
        }
        .task { if !model.hasLoaded { await model.refresh() } }
        .confirmationDialog("Move \(model.selected.count) sessions to the Trash?", isPresented: $confirming) {
            Button("Move \(Format.bytes(model.selectedSize)) to Trash") { Task { await model.moveSelectedToTrash() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't be able to /resume these sessions, and their usage history leaves AI Usage. They stay in the Trash until you empty it.")
        }
        .confirmationDialog("Compress \(model.selected.count) sessions?", isPresented: $confirmingCompress) {
            Button("Compress \(Format.bytes(model.selectedSize))") { Task { await model.compressSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each transcript is compressed to roughly a third of its size and kept in MacSweep's archive. A compressed session can't be resumed, and its usage leaves AI Usage, until you restore it from the Archived list. Named and open sessions are skipped.")
        }
        .confirmationDialog("Slim \(model.selected.count) sessions?", isPresented: $confirmingSlim) {
            Button("Move \(Format.bytes(model.selectedExtrasSize)) of Extras to Trash") { Task { await model.slimSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps every conversation, so the sessions stay in your history. Removes their subagent logs, saved tool output and file backups, so /rewind and opening a subagent's log stop working for them.")
        }
    }

    private var controls: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Claude Code & Codex sessions",
                              subtitle: "Slim a session to keep its conversation and drop the bulky extras, or move the whole session to the Trash. Named and open sessions are never auto-selected.")
                HStack {
                    TextField("Search title, project or id", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    Picker("Tool", selection: $provider) {
                        Text("All tools").tag(AIProvider?.none)
                        ForEach(AIProvider.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    .fixedSize()
                    Picker("Age", selection: $minimumAge) {
                        Text("Any age").tag(0)
                        ForEach([7, 30, 60, 90], id: \.self) { Text("Older than \($0) days").tag($0) }
                    }
                    .fixedSize()
                    Spacer()
                    Menu("Select") {
                        Button("Everything with extras to slim (\(Format.bytes(model.extrasSize)))") { model.selectSlimmable() }
                        Divider()
                        ForEach([14, 30, 60, 90], id: \.self) { days in
                            Button("Older than \(days) days (\(Format.bytes(oldSize(days))))") { model.selectOlder(than: days) }
                        }
                        Divider()
                        Button("Clear selection") { model.selected.removeAll() }
                    }
                    .fixedSize()
                    Button("Slim…") { confirmingSlim = true }.disabled(model.selectedExtrasSize == 0 || model.isRemoving)
                        .help("Keep the conversation, remove subagent logs, tool output and file backups")
                    Button(model.progress.map { "Compressing \($0)…" } ?? "Compress…") { confirmingCompress = true }
                        .disabled(model.selected.isEmpty || model.isRemoving)
                        .help("Shrink the transcript to about a third; restore it any time to resume")
                    Button("Move to Trash…") { confirming = true }.disabled(model.selected.isEmpty || model.isRemoving)
                    Button("Rescan", systemImage: "arrow.clockwise") { Task { await model.refresh() } }.disabled(model.isLoading)
                }
            }
        }
    }

    @ViewBuilder private var list: some View {
        if model.isLoading && !model.hasLoaded {
            Card { HStack { ProgressView().controlSize(.small); Text("Measuring sessions…").foregroundStyle(.secondary) } }
        } else if filtered.isEmpty {
            Card { Label(model.sessions.isEmpty ? "No Claude Code or Codex sessions found." : "No sessions match these filters.", systemImage: "tray") }
        } else {
            Card(padding: 8) {
                LazyVStack(spacing: 0) {
                    ForEach(filtered.prefix(limit)) { session in
                        SessionRow(session: session, name: model.name(of: session), isNamed: model.isNamed(session), tint: accent,
                                   isSelected: binding(session))
                        Divider()
                    }
                    if filtered.count > limit {
                        Button("Show \(min(100, filtered.count - limit)) more of \(filtered.count)") { limit += 100 }.buttonStyle(.link).padding(10)
                    }
                }
            }
        }
    }

    private var filtered: [AISessionRecord] {
        model.sessions.filter { session in
            (provider == nil || session.provider == provider) && session.age() >= minimumAge
                && (search.isEmpty || session.project.localizedCaseInsensitiveContains(search) || session.id.localizedCaseInsensitiveContains(search)
                    || (session.title?.localizedCaseInsensitiveContains(search) ?? false)
                    || (model.name(of: session)?.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    private func oldSize(_ days: Int) -> UInt64 {
        SessionInventory.old(model.sessions, olderThanDays: days, keeping: Set(model.names.keys)).reduce(0) { $0 + $1.size }
    }

    private func binding(_ session: AISessionRecord) -> Binding<Bool> {
        Binding(get: { model.selected.contains(session.id) },
                set: { if $0, !session.isActive() { model.selected.insert(session.id) } else { model.selected.remove(session.id) } })
    }
}

private struct SessionRow: View {
    let session: AISessionRecord
    let name: String?
    let isNamed: Bool
    let tint: Color
    @Binding var isSelected: Bool
    private var isActive: Bool { session.isActive() }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Select session", isOn: $isSelected).labelsHidden().toggleStyle(.checkbox).disabled(isActive)
                .help(isActive ? "Still open: written to in the last 15 minutes" : "")
            Image(systemName: session.provider == .codex ? "terminal" : "flame").foregroundStyle(tint).frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name ?? session.title ?? session.project).font(.callout.weight(.semibold)).lineLimit(1)
                    if isActive { Text("Open").font(.caption2.weight(.semibold)).foregroundStyle(.green).padding(.horizontal, 6).padding(.vertical, 1).background(Color.green.opacity(0.15), in: Capsule()) }
                    if isNamed { Text("Named").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1).background(tint.opacity(0.18), in: Capsule()) }
                }
                Text("\(name == nil && session.title == nil ? "" : session.project + " · ")\(session.id.prefix(8))\(session.extrasSize > 0 ? " · \(Format.bytes(session.extrasSize)) of extras" : "")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(session.modified.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
            Text(Format.bytes(session.size)).font(.callout.monospacedDigit()).frame(width: 80, alignment: .trailing)
            Button("Reveal", systemImage: "folder") { FileActions.reveal(session.paths[0]) }.labelStyle(.iconOnly).buttonStyle(.borderless)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}

/// Compressed sessions, each with a button that puts it back exactly as it was.
private struct ArchivedSessionsCard: View {
    let model: AISessionsModel
    @State private var isOpen = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionHeader(title: "Archived (\(model.archived.count))", subtitle: "Compressed transcripts, saving \(Format.bytes(model.archivedSaved)). Restore one to resume it.")
                    Spacer()
                    Button(isOpen ? "Hide" : "Show") { isOpen.toggle() }
                }
                if isOpen {
                    ForEach(model.archived) { record in
                        HStack(spacing: 10) {
                            Image(systemName: "archivebox").foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.title ?? record.project).font(.callout.weight(.semibold)).lineLimit(1)
                                Text("\(record.project) · \(record.id.prefix(8)) · last used \(Format.relative(record.modified))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text("\(Format.bytes(record.archivedSize)) of \(Format.bytes(record.originalSize))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Button("Restore") { Task { await model.restore(record) } }.disabled(model.isRemoving)
                        }
                    }
                }
            }
        }
    }
}
