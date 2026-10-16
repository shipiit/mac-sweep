import Darwin
import MacSweepCore
import SwiftUI

enum ProcessFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case mine = "Mine"
    case apps = "Apps"
    case growing = "Growing memory"

    var id: String { rawValue }
}

struct ProcessesView: View {
    @Environment(AppModel.self) private var app
    @State private var search = ""
    @State private var filter: ProcessFilter = .all
    @State private var selection: Int32?
    @State private var sortOrder = [KeyPathComparator(\ProcessRow.memory, order: .reverse)]
    @State private var killRequest: KillRequest?
    @State private var showsInspector = true
    @AppStorage("groupProcesses") private var grouped = true

    var body: some View {
        let model = app.processes
        VStack(spacing: 14) {
            if let stats = model.memory { MemoryOverview(stats: stats) }
            IdleAppsPanel()
            if grouped {
                GroupedProcessList(rows: visibleRows(model.rows), selection: $selection) { killRequest = $0 }
                    .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                table(rows: visibleRows(model.rows))
            }
        }
        .padding(20)
        .navigationTitle("Processes & Memory")
        .navigationSubtitle("\(model.rows.count) processes · updates every 3s")
        .searchable(text: $search, prompt: "Name, PID or user")
        .toolbar { toolbar(model) }
        .inspector(isPresented: $showsInspector) {
            Group {
                if let pid = selection, let row = model.row(pid: pid) {
                    ProcessInspector(row: row, samples: model.samples(for: pid), ports: app.ports.ports.filter { $0.pid == pid }) {
                        killRequest = $0
                    }
                } else {
                    ContentUnavailableView("No process selected", systemImage: "cpu", description: Text("Select a process to see its memory history, command line and open ports."))
                }
            }
            .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
        .killFlow($killRequest) { Task { await model.refresh() } }
    }

    private func table(rows: [ProcessRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: 6) {
                    ProcessIcon(pid: row.pid, path: row.snapshot.path)
                    Text(row.name).lineLimit(1)
                    if row.trend.isSteadilyGrowing {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(.orange)
                            .help("Memory has grown steadily while MacSweep has been watching")
                            .accessibilityLabel("Memory growing")
                    }
                }
            }
            .width(min: 180, ideal: 260)
            TableColumn("Memory", value: \.memory) { row in
                Text(Format.bytes(row.snapshot.memory.map { $0 }))
                    .monospacedDigit()
                    .foregroundStyle(row.snapshot.memory == nil ? .tertiary : .primary)
            }
            .width(min: 80, ideal: 90)
            TableColumn("Trend /min", value: \.growthPerMinute) { row in
                TrendText(trend: row.trend)
            }
            .width(min: 80, ideal: 95)
            TableColumn("CPU %", value: \.cpu) { row in
                Text(Format.percent(row.cpu)).monospacedDigit()
            }
            .width(min: 55, ideal: 60)
            TableColumn("Threads", value: \.threads) { row in
                Text(row.snapshot.threads.map(String.init) ?? "—").monospacedDigit()
            }
            .width(min: 50, ideal: 60)
            TableColumn("PID", value: \.pid) { row in
                Text(String(row.pid)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60)
            TableColumn("User", value: \.user) { row in
                Text(row.user).foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 90)
        }
        .contextMenu(forSelectionType: Int32.self) { pids in
            if let pid = pids.first, let row = app.processes.row(pid: pid) {
                Button("Quit") { killRequest = KillRequest(pid: pid, name: row.name, force: false) }
                Button("Force Kill") { killRequest = KillRequest(pid: pid, name: row.name, force: true) }
                Divider()
                if let path = row.snapshot.path {
                    Button("Reveal in Finder") { FileActions.reveal(path) }
                }
                Button("Copy PID") { FileActions.copy(String(pid)) }
            }
        }
        .onDeleteCommand {
            if let pid = selection, let row = app.processes.row(pid: pid) {
                killRequest = KillRequest(pid: pid, name: row.name, force: false)
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ model: ProcessModel) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Filter", selection: $filter) {
                ForEach(ProcessFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("View", selection: $grouped) {
                Label("By app", systemImage: "square.stack.3d.up").tag(true)
                Label("All processes", systemImage: "list.bullet").tag(false)
            }
            .pickerStyle(.segmented)
            .help("Group helpers under their app, or list every process")
            Button(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill") {
                model.isPaused.toggle()
            }
            .help(model.isPaused ? "Resume live updates" : "Pause live updates")
            Button("Quit Process", systemImage: "xmark.octagon") {
                if let pid = selection, let row = model.row(pid: pid) { killRequest = KillRequest(pid: pid, name: row.name, force: false) }
            }
            .disabled(selection == nil)
            .help("Quit the selected process (⌫)")
            Button("Inspector", systemImage: "sidebar.trailing") { showsInspector.toggle() }
        }
    }

    private func visibleRows(_ rows: [ProcessRow]) -> [ProcessRow] {
        let me = getuid()
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return rows.filter { row in
            switch filter {
            case .all: true
            case .mine: row.snapshot.uid == me
            case .apps: row.snapshot.path?.contains(".app/Contents/MacOS/") == true
            case .growing: row.trend.isSteadilyGrowing
            }
        }
        .filter { row in
            query.isEmpty || row.name.lowercased().contains(query) || String(row.pid) == query || row.user.lowercased().contains(query)
        }
        .sorted(using: sortOrder)
    }
}

struct TrendText: View {
    let trend: MemoryTrendSummary

    var body: some View {
        let perMinute = Int64(trend.bytesPerMinute.rounded())
        Text(abs(perMinute) < 64 << 10 ? "—" : Format.signedBytes(perMinute))
            .monospacedDigit()
            .foregroundStyle(trend.isSteadilyGrowing ? .orange : .secondary)
    }
}
