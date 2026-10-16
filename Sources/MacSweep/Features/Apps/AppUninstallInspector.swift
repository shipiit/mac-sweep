import MacSweepCore
import SwiftUI

struct AppUninstallInspector: View {
    let installed: InstalledApp
    let model: AppsModel
    @State private var included = Set<String>()
    @State private var confirm = false

    var body: some View {
        let leftovers = model.leftovers[installed.id]
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    FileIcon(path: installed.path, size: 52)
                    VStack(alignment: .leading) {
                        Text(installed.name).font(.title3.weight(.semibold))
                        Text("\(installed.version) · \(installed.bundleID)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                InfoGrid(rows: [
                    ("App size", installed.size.map(Format.bytes) ?? "…"),
                    ("Leftovers", leftovers.map { Format.bytes($0.reduce(0) { $0 + $1.size }) } ?? "…"),
                    ("Last used", installed.lastUsed.map { Format.relative($0) } ?? "Unknown"),
                ])
                Text("Also remove").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let leftovers {
                    if leftovers.isEmpty { Text("No leftovers found.").foregroundStyle(.secondary) }
                    ForEach(leftovers) { item in
                        Toggle(isOn: Binding(get: { included.contains(item.path) },
                                             set: { if $0 { included.insert(item.path) } else { included.remove(item.path) } })) {
                            HStack {
                                Text(Format.path(item.path)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Format.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
                Button("Uninstall \(installed.name)…", role: .destructive) { confirm = true }
                    .buttonStyle(.borderedProminent).tint(.red)
                if model.isRunning(installed) {
                    Label("\(installed.name) is running. Quit it first.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
            }
            .padding(16)
        }
        .task(id: installed.id) {
            await model.loadLeftovers(for: installed)
            included = Set((model.leftovers[installed.id] ?? []).map(\.path))
        }
        .confirmationDialog("Move \(installed.name) and \(included.count) leftovers to the Trash?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) { Task { await model.uninstall(installed, includeLeftovers: included) } }
        } message: {
            Text("You can restore everything from the Trash until you empty it.")
        }
    }
}
