import MacSweepCore
import SwiftUI

struct TrashBinsView: View {
    @State private var bins: [TrashBin]?
    @State private var isLoading = false
    @State private var confirm: TrashBin?
    @State private var message: String?

    var body: some View {
        Group {
            if let bins {
                List {
                    Section {
                        if bins.isEmpty { Text("No Trash folders found. Grant Full Disk Access to see your Mac's Trash.").foregroundStyle(.secondary) }
                        ForEach(bins) { bin in
                            HStack(spacing: 12) {
                                Image(systemName: bin.name == "Mac Trash" ? "trash.fill" : "externaldrive.fill").font(.title2)
                                    .foregroundStyle(.secondary).frame(width: 32)
                                VStack(alignment: .leading) {
                                    Text(bin.name).fontWeight(.medium)
                                    Text("\(bin.itemCount) items").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Format.bytes(bin.size)).monospacedDigit().fontWeight(.semibold)
                                Button("Open") { FileActions.open(bin.path) }
                                Button("Empty…", role: .destructive) { confirm = bin }.disabled(bin.itemCount == 0)
                            }
                            .padding(.vertical, 4)
                        }
                    } footer: {
                        Text("Emptying is permanent. Total: \(Format.bytes(bins.reduce(0) { $0 + $1.size }))").font(.caption)
                    }
                }
            } else {
                ModuleIntro(title: "Trash Bins", subtitle: "Empty every Trash on your Mac, including the ones on external drives.",
                            symbol: "trash.fill", tint: .orange,
                            bullets: [("externaldrive", "Every drive", "Finds the hidden Trash folders on USB and external disks."),
                                      ("lock.open", "Locked items too", "Removes items Finder refuses because they're locked.")],
                            actionTitle: "Find Trash", isWorking: isLoading) { Task { await load() } }
            }
        }
        .navigationTitle("Trash Bins")
        .toolbar { if bins != nil { Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } } } }
        .confirmationDialog("Empty \(confirm?.name ?? "") permanently?", isPresented: isPresented($confirm), titleVisibility: .visible, presenting: confirm) { bin in
            Button("Empty \(Format.bytes(bin.size))", role: .destructive) {
                Task {
                    let result = await Task.detached { TrashBins.empty(bin) }.value
                    message = result.failed.isEmpty ? "Removed \(result.removed) items." : "Removed \(result.removed); \(result.failed.count) couldn't be deleted."
                    await load()
                }
            }
        } message: { _ in Text("Items in the Trash are deleted for good.") }
        .alert(message ?? "", isPresented: isPresented($message)) { Button("OK", role: .cancel) {} }
    }

    private func load() async {
        isLoading = true
        bins = await Task.detached { TrashBins.list() }.value
        isLoading = false
    }
}

struct MailAttachmentsView: View {
    @State private var items: [MailStorageItem]?
    @State private var isLoading = false
    @State private var selected = Set<String>()
    @State private var confirm = false
    @State private var message: String?

    var body: some View {
        Group {
            if let items {
                VStack(spacing: 0) {
                    List(items, selection: $selected) { item in
                        HStack {
                            Image(systemName: item.kind == .downloads ? "paperclip" : "envelope").frame(width: 24).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.kind.rawValue).fontWeight(.medium)
                                Text(Format.path(item.path)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                Text(item.kind == .downloads ? "Safe: these are copies; originals stay in your mailbox."
                                     : "Mail re-downloads these for iCloud, Gmail and other IMAP/Exchange accounts. POP accounts may lose them.")
                                    .font(.caption).foregroundStyle(item.kind == .downloads ? .green : .orange)
                            }
                            Spacer()
                            Text(Format.bytes(item.size)).monospacedDigit()
                        }
                        .tag(item.path)
                    }
                    .overlay { if items.isEmpty { ContentUnavailableView("No Mail attachments found", systemImage: "envelope", description: Text("Grant Full Disk Access if you use Apple Mail.")) } }
                    HStack {
                        Text("Select items, then move them to the Trash.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Move to Trash…") { confirm = true }.buttonStyle(.borderedProminent).disabled(selected.isEmpty)
                    }
                    .padding(12)
                    .background(.bar)
                }
            } else {
                ModuleIntro(title: "Mail Attachments", subtitle: "Reclaim space taken by attachments Apple Mail keeps on your disk.",
                            symbol: "paperclip", tint: .blue,
                            bullets: [("tray.and.arrow.down", "Downloaded copies", "Files Mail saved when you opened attachments."),
                                      ("icloud.and.arrow.down", "Cached attachments", "Server accounts download them again whenever you open the message.")],
                            actionTitle: "Scan Mail", isWorking: isLoading) { Task { await load() } }
            }
        }
        .navigationTitle("Mail Attachments")
        .confirmationDialog("Move \(selected.count) folders to the Trash?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                let targets = (items ?? []).filter { selected.contains($0.path) }.map { CleanupTarget(path: $0.path, size: $0.size) }
                let results = Cleaner.remove(targets, mode: .trash)
                message = "Moved \(results.filter(\.succeeded).count) of \(results.count) to the Trash. Quit Mail first if any failed."
                selected.removeAll()
                Task { await load() }
            }
        }
        .alert(message ?? "", isPresented: isPresented($message)) { Button("OK", role: .cancel) {} }
    }

    private func load() async {
        isLoading = true
        items = await Task.detached { MailAttachments.scan() }.value
        isLoading = false
    }
}
