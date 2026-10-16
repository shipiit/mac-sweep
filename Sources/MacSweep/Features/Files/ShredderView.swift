import AppKit
import MacSweepCore
import SwiftUI
import UniformTypeIdentifiers

struct ShredderView: View {
    @State private var files: [String] = []
    @State private var confirm = false
    @State private var results: [Shredder.Outcome] = []
    @State private var dropTargeted = false
    @State private var sizes: [String: UInt64] = [:]

    var body: some View {
        Group {
            if files.isEmpty && results.isEmpty {
                ModuleIntro(title: "Shredder", subtitle: "Permanently delete files and folders, skipping the Trash. Drop them anywhere here.",
                            symbol: "doc.badge.ellipsis", tint: .indigo,
                            bullets: [("lock.open", "Gets around Finder errors", "Removes locked items that Finder refuses to delete."),
                                      ("lock.shield", "Honest about SSDs", "On SSDs no app can guarantee old data is overwritten. FileVault keeps deleted data unreadable.")],
                            actionTitle: "Select Files…") { pick() }
            } else {
                List {
                    if !files.isEmpty {
                        Section("To shred") {
                            ForEach(files, id: \.self) { path in
                                HStack {
                                    FileIcon(path: path)
                                    Text(Format.path(path)).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(sizes[path].map(Format.bytes) ?? "…").monospacedDigit().foregroundStyle(.secondary)
                                    Button { files.removeAll { $0 == path } } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.borderless).accessibilityLabel("Remove \(path) from list")
                                }
                            }
                        }
                    }
                    if !results.isEmpty {
                        Section("Result") {
                            ForEach(results, id: \.path) { result in
                                Label(Format.path(result.path) + (result.error.map { ": \($0)" } ?? ""),
                                      systemImage: result.error == nil ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(result.error == nil ? .green : .red)
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button("Add Files…") { pick() }
                        Spacer()
                        Button("Shred \(files.count) Items…", role: .destructive) { confirm = true }
                            .buttonStyle(.borderedProminent).tint(.red).disabled(files.isEmpty)
                    }
                    .padding(12).background(.bar)
                }
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.red, style: StrokeStyle(lineWidth: 3, dash: [8])).padding(12)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let path = url?.path else { return }
                    Task { @MainActor in if !files.contains(path) { files.append(path) } }
                }
            }
            return true
        }
        .task(id: files) {
            for path in files where sizes[path] == nil {
                sizes[path] = await Task.detached { DiskScanner.measure(path) ?? 0 }.value
            }
        }
        .navigationTitle("Shredder")
        .confirmationDialog("Permanently delete \(files.count) items?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Shred", role: .destructive) {
                results = Shredder.shred(files)
                files.removeAll()
            }
        } message: {
            Text("They skip the Trash and can't be restored. Keys, system folders and MacSweep itself are always refused.")
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            results = []
            files += panel.urls.map(\.path).filter { !files.contains($0) }
        }
    }
}
