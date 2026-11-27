import MacSweepCore
import SwiftUI

/// Databases on every running local Postgres server: who uses each, when it last changed, and what's inside.
struct DatabasesCard: View {
    @Bindable var model: HiddenSpaceModel
    @State private var filter: PostgresDatabase.Kind?
    @State private var oldestFirst = false
    @State private var confirming = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    SectionHeader(title: "Postgres databases",
                                  subtitle: model.servers.isEmpty ? "No local Postgres server is running. Start it to see its databases."
                                      : "On " + model.servers.map { "\($0.name) (port \($0.port))" }.joined(separator: ", ") + ". Open a row to see its biggest tables and the project files that name it.")
                    Spacer()
                    Menu("Select") {
                        Button("Test leftovers (\(model.testLeftovers.count))") { model.selectTestLeftovers() }
                        ForEach([90, 180, 365], id: \.self) { days in
                            Button("Unused by any project, untouched for \(days) days") { model.selectUntouched(days: days) }
                        }
                        Divider()
                        Button("Clear selection") { model.selectedDatabases.removeAll() }
                    }
                    .fixedSize().disabled(model.databases.isEmpty)
                    Button("Drop \(model.selectedDatabases.count) Selected…") { confirming = true }
                        .disabled(model.selectedDatabases.isEmpty || model.busy != nil)
                }
                if !model.databases.isEmpty {
                    HStack {
                        Picker("Show", selection: $filter) {
                            Text("All (\(model.databases.filter { $0.kind != .system }.count))").tag(PostgresDatabase.Kind?.none)
                            ForEach([PostgresDatabase.Kind.test, .unreferenced, .referenced, .inUse], id: \.self) { kind in
                                Text("\(kind.rawValue) (\(model.databases.filter { $0.kind == kind }.count))").tag(Optional(kind))
                            }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        Toggle("Oldest first", isOn: $oldestFirst).toggleStyle(.checkbox).fixedSize()
                            .help("Sort by when each database last changed instead of by size")
                    }
                    if shown.isEmpty {
                        Label("No databases of this kind.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    }
                    ForEach(shown) { database in
                        DatabaseRow(database: database, model: model, isSelected: binding(database))
                        if database.id != shown.last?.id { Divider() }
                    }
                    if shown.count < filtered.count {
                        Text("Showing the first 60 of \(filtered.count).").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .confirmationDialog("Drop \(model.selectedDatabases.count) databases (\(Format.bytes(model.selectedDatabaseSize)))?", isPresented: $confirming) {
            Button("Back Up, Then Drop") { Task { await model.dropSelectedDatabases(backUp: true) } }
            Button("Drop Without Backup", role: .destructive) { Task { await model.dropSelectedDatabases(backUp: false) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A dropped database doesn't go to the Trash. Backing up first saves a compressed copy of each in ~/MacSweep Backups/Postgres and checks it can be read; a database whose backup fails is not dropped. Postgres refuses any database that is in use.")
        }
    }

    private var filtered: [PostgresDatabase] {
        let matching = model.databases.filter { filter == nil ? $0.kind != .system : $0.kind == filter }
        return oldestFirst ? matching.sorted { ($0.lastWritten ?? .distantFuture) < ($1.lastWritten ?? .distantFuture) } : matching.sorted { $0.size > $1.size }
    }

    private var shown: [PostgresDatabase] { Array(filtered.prefix(60)) }

    private func binding(_ database: PostgresDatabase) -> Binding<Bool> {
        Binding(get: { model.selectedDatabases.contains(database.id) },
                set: { if $0 { model.selectedDatabases.insert(database.id) } else { model.selectedDatabases.remove(database.id) } })
    }
}

private struct DatabaseRow: View {
    let database: PostgresDatabase
    let model: HiddenSpaceModel
    @Binding var isSelected: Bool
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("Select \(database.name)", isOn: $isSelected).labelsHidden().toggleStyle(.checkbox).disabled(!database.isRemovable)
                Button { isOpen.toggle() } label: {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right").frame(width: 12)
                }
                .buttonStyle(.borderless).accessibilityLabel(isOpen ? "Hide details" : "Show tables and where it's used")
                VStack(alignment: .leading, spacing: 1) {
                    Text(database.name).font(.callout.monospaced()).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Pill(text: database.kind.rawValue, color: color)
                Text(Format.bytes(database.size)).font(.callout.monospacedDigit()).frame(width: 80, alignment: .trailing)
            }
            if isOpen { details.padding(.leading, 52).task { await model.loadTables(of: database) } }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let tables = model.tables[database.id] {
                if tables.isEmpty {
                    Text("No tables, or the database couldn't be opened.").font(.caption).foregroundStyle(.secondary)
                } else {
                    let largest = max(tables.first?.size ?? 1, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Biggest tables").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(tables) { table in
                            HStack(spacing: 8) {
                                Text(table.name).font(.caption.monospaced()).lineLimit(1).frame(width: 260, alignment: .leading)
                                ProgressView(value: Double(table.size) / Double(largest)).frame(maxWidth: 160).accessibilityHidden(true)
                                Text("\(Format.count(table.rows)) rows").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Spacer()
                                Text(Format.bytes(table.size)).font(.caption.monospacedDigit())
                            }
                        }
                    }
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Reading tables…").font(.caption).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(database.referencedBy.isEmpty ? "No project config file names this database." : "Named in").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(database.referencedBy, id: \.self) { file in
                    Button("~/" + file) { FileActions.reveal(NSHomeDirectory() + "/" + file) }.buttonStyle(.link).font(.caption.monospaced())
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var detail: String {
        var parts: [String] = []
        if database.kind == .inUse { parts.append("\(database.connections) open connection\(database.connections == 1 ? "" : "s")") }
        if let written = database.lastWritten { parts.append("last changed \(Format.relative(written))") }
        parts.append("port \(database.port)")
        if let first = database.referencedBy.first {
            parts.append("in ~/" + first + (database.referencedBy.count > 1 ? " +\(database.referencedBy.count - 1)" : ""))
        }
        return parts.joined(separator: " · ")
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
