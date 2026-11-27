import MacSweepCore
import SwiftUI

/// Leftover Chrome / Brave / Edge app copies in the temp area.
struct BrowserCopiesCard: View {
    let model: HiddenSpaceModel
    @State private var confirming = false

    var body: some View {
        let running = model.runningBrowsers()
        let blocked = Set(model.clones.map(\.bundleID)).filter(running.contains)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    SectionHeader(title: "Browser code-sign copies",
                                  subtitle: "Chromium browsers copy themselves here at launch and leave the copy behind after a crash, force-quit or restart. They're throwaway: the browser makes a fresh one next time.")
                    Spacer()
                    Button("Delete \(model.clones.count) Copies") { confirming = true }
                        .disabled(model.clones.isEmpty || model.busy != nil || !blocked.isEmpty)
                }
                if model.clones.isEmpty {
                    Label("No leftover copies.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    let byBrowser = Dictionary(grouping: model.clones, by: \.bundleID)
                    ForEach(byBrowser.keys.sorted(), id: \.self) { id in
                        let clones = byBrowser[id] ?? []
                        HStack {
                            Text(id).font(.callout.monospaced())
                            if running.contains(id) { Text("Running — quit it first").font(.caption).foregroundStyle(.orange) }
                            Spacer()
                            Text("\(clones.count) copies · up to \(Format.bytes(clones.reduce(0) { $0 + $1.size }))").font(.callout.monospacedDigit())
                        }
                    }
                    Text("Copies of the same browser version share disk blocks, so the space you get back is often smaller than the total shown.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Delete \(model.clones.count) browser copies?", isPresented: $confirming) {
            Button("Delete Copies", role: .destructive) { Task { await model.removeClones() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They're deleted right away (not moved to the Trash) because they are temporary copies of the browser app itself.")
        }
    }
}

/// Installed iOS / watchOS / visionOS simulator runtimes.
struct RuntimesCard: View {
    let model: HiddenSpaceModel
    @State private var pending: SimulatorRuntime?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Simulator runtimes", subtitle: "Each runtime is a disk image outside your home folder. Xcode downloads one again if a project needs it.")
                if model.runtimes.isEmpty {
                    Label("No simulator runtimes installed.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                ForEach(model.runtimes) { runtime in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(runtime.name).font(.callout.weight(.semibold))
                            Text(runtime.lastUsed.map { "Last used \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Never used")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.bytes(runtime.size)).font(.callout.monospacedDigit())
                        Button("Delete") { pending = runtime }.disabled(!runtime.isDeletable || model.busy != nil)
                    }
                }
            }
        }
        .confirmationDialog("Delete \(pending?.name ?? "runtime")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            presenting: pending) { runtime in
            Button("Delete Runtime", role: .destructive) { Task { await model.deleteRuntime(runtime) } }
            Button("Cancel", role: .cancel) {}
        } message: { runtime in
            Text("Frees about \(Format.bytes(runtime.size)). Simulators using it stop working until Xcode downloads it again.")
        }
    }
}

/// Databases on every running local Postgres server, marked by whether a project uses them.
struct DatabasesCard: View {
    @Bindable var model: HiddenSpaceModel
    @State private var filter: PostgresDatabase.Kind?
    @State private var confirming = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    SectionHeader(title: "Postgres databases",
                                  subtitle: model.servers.isEmpty ? "No local Postgres server is running. Start it to see its databases."
                                      : "On " + model.servers.map { "\($0.name) (port \($0.port))" }.joined(separator: ", ") + ". \"Used by a project\" means a config file in your projects names it.")
                    Spacer()
                    Button("Select Test Leftovers") { model.selectTestLeftovers() }.disabled(model.testLeftovers.isEmpty)
                    Button("Drop \(model.selectedDatabases.count) Selected…") { confirming = true }
                        .disabled(model.selectedDatabases.isEmpty || model.busy != nil)
                }
                if !model.databases.isEmpty {
                    Picker("Show", selection: $filter) {
                        Text("All (\(model.databases.count))").tag(PostgresDatabase.Kind?.none)
                        ForEach([PostgresDatabase.Kind.test, .unreferenced, .referenced, .inUse], id: \.self) { kind in
                            Text("\(kind.rawValue) (\(model.databases.filter { $0.kind == kind }.count))").tag(Optional(kind))
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    if shown.isEmpty {
                        Label("No databases of this kind.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    }
                    ForEach(shown) { database in DatabaseRow(database: database, isSelected: binding(database)) }
                    if shown.count < filtered.count {
                        Text("Showing the 60 largest of \(filtered.count).").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .confirmationDialog("Permanently drop \(model.selectedDatabases.count) databases?", isPresented: $confirming) {
            Button("Drop \(Format.bytes(model.selectedDatabaseSize))", role: .destructive) { Task { await model.dropSelectedDatabases() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone: dropped databases don't go to the Trash. Postgres refuses any database that is in use.")
        }
    }

    private var filtered: [PostgresDatabase] { model.databases.filter { filter == nil ? $0.kind != .system : $0.kind == filter } }
    private var shown: [PostgresDatabase] { Array(filtered.prefix(60)) }

    private func binding(_ database: PostgresDatabase) -> Binding<Bool> {
        Binding(get: { model.selectedDatabases.contains(database.id) },
                set: { if $0 { model.selectedDatabases.insert(database.id) } else { model.selectedDatabases.remove(database.id) } })
    }
}

private struct DatabaseRow: View {
    let database: PostgresDatabase
    @Binding var isSelected: Bool
    @State private var showsFiles = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row
            if showsFiles {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(database.referencedBy, id: \.self) { file in
                        Button("~/" + file) { FileActions.reveal(NSHomeDirectory() + "/" + file) }
                            .buttonStyle(.link).font(.caption.monospaced())
                    }
                }
                .padding(.leading, 30)
            }
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            Toggle("Select \(database.name)", isOn: $isSelected).labelsHidden().toggleStyle(.checkbox).disabled(!database.isRemovable)
            VStack(alignment: .leading, spacing: 1) {
                Text(database.name).font(.callout.monospaced())
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(database.kind.rawValue).font(.caption.weight(.semibold)).foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 2).background(color.opacity(0.15), in: Capsule())
            if !database.referencedBy.isEmpty {
                Button(showsFiles ? "Hide files" : "Where used") { showsFiles.toggle() }.buttonStyle(.link).font(.caption)
            }
            Text(Format.bytes(database.size)).font(.callout.monospacedDigit()).frame(width: 80, alignment: .trailing)
        }
    }

    private var detail: String {
        if database.kind == .inUse { return "\(database.connections) open connection\(database.connections == 1 ? "" : "s") · port \(database.port)" }
        if let first = database.referencedBy.first { return "Used in ~/" + first + (database.referencedBy.count > 1 ? " and \(database.referencedBy.count - 1) more" : "") }
        return "port \(database.port)"
    }

    private var color: Color {
        switch database.kind {
        case .test: .green
        case .unreferenced: .orange
        case .referenced, .inUse: .blue
        case .system: .secondary
        }
    }
}
