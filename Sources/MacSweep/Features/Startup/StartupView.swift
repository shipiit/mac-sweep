import MacSweepCore
import SwiftUI

struct StartupView: View {
    @Environment(AppModel.self) private var app
    @State private var search = ""
    @State private var scope: LaunchScope?
    @State private var selection: LaunchItem.ID?
    @State private var sortOrder = [KeyPathComparator(\LaunchItem.label)]
    @State private var tab: StartupTab = .loginItems

    enum StartupTab: String, CaseIterable, Identifiable {
        case loginItems = "Login Items"
        case agents = "Agents & Daemons"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch tab {
            case .loginItems:
                LoginItemsView().navigationTitle("Startup Items")
            case .agents:
                agentsView
            }
        }
        .sectionTabs(StartupTab.allCases, selection: $tab, title: \.rawValue)
    }

    private var agentsView: some View {
        @Bindable var model = app.startup
        let rows = visible(model.items)
        return VStack(spacing: 0) {
            Picker("Scope", selection: $scope) {
                Text("All").tag(LaunchScope?.none)
                ForEach(LaunchScope.allCases, id: \.self) { Text($0.rawValue).tag(LaunchScope?.some($0)) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().padding(.vertical, 8)
            if rows.isEmpty && !model.isLoading {
                ContentUnavailableView("No startup items", systemImage: "power", description: Text("No launch agents or daemons match."))
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.label) { item in
                        HStack(spacing: 6) {
                            if let executable = item.executable { FileIcon(path: executable) }
                            Text(item.label).lineLimit(1)
                        }
                    }
                    .width(min: 220, ideal: 320)
                    TableColumn("Status") { item in StatusBadge(status: model.status(of: item)) }
                        .width(min: 100, ideal: 120)
                    TableColumn("Scope") { item in Text(item.scope.rawValue).foregroundStyle(.secondary) }
                        .width(min: 100, ideal: 120)
                    TableColumn("At login") { item in
                        Text(item.runAtLoad ? "Yes" : "No").foregroundStyle(item.runAtLoad ? .primary : .secondary)
                    }
                    .width(min: 55, ideal: 65)
                    TableColumn("Keep alive") { item in
                        Text(item.keepAlive ? "Yes" : "No").foregroundStyle(item.keepAlive ? .primary : .secondary)
                    }
                    .width(min: 60, ideal: 70)
                    TableColumn("Program") { item in
                        Text(item.executable.map(Format.path) ?? "—")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .navigationTitle("Startup Items")
        .navigationSubtitle("\(model.items.count) launch agents & daemons")
        .searchable(text: $search, prompt: "Label or program")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Login Items", systemImage: "person.crop.circle.badge.checkmark") {
                    FileActions.open(url: Permissions.loginItemsSettingsURL)
                }
                .help("Open Login Items & Extensions in System Settings")
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        .inspector(isPresented: .constant(true)) {
            Group {
                if let id = selection, let item = model.items.first(where: { $0.id == id }) {
                    StartupInspector(item: item, model: model)
                } else {
                    ContentUnavailableView("Select an item", systemImage: "power", description: Text("Stop, disable or inspect what launches with your Mac."))
                }
            }
            .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
        .alert("Couldn't change item", isPresented: isPresented($model.error), presenting: model.error) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
        .task { await model.refresh() }
    }

    private func visible(_ items: [LaunchItem]) -> [LaunchItem] {
        let query = search.lowercased()
        return items
            .filter { scope == nil || $0.scope == scope }
            .filter { query.isEmpty || $0.label.lowercased().contains(query) || ($0.executable?.lowercased().contains(query) ?? false) }
            .sorted(using: sortOrder)
    }
}

struct StatusBadge: View {
    let status: StartupModel.Status

    var body: some View {
        switch status {
        case .running: Pill(text: status.title, color: .green)
        case .loaded: Pill(text: status.title, color: .blue)
        case .failed: Pill(text: status.title, color: .red)
        case .disabled: Pill(text: status.title, color: .secondary)
        case .notLoaded: Pill(text: status.title, color: .secondary)
        }
    }
}

struct StartupInspector: View {
    let item: LaunchItem
    let model: StartupModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.label).font(.title3.weight(.semibold)).textSelection(.enabled)
                    HStack {
                        StatusBadge(status: model.status(of: item))
                        Pill(text: item.scope.rawValue)
                    }
                }
                HStack {
                    ForEach([LaunchAction.stop, .disable, .enable], id: \.self) { action in
                        Button(action.rawValue) { Task { await model.perform(action, on: item) } }
                            .disabled(model.busyItem != nil)
                    }
                    if model.busyItem == item.id { ProgressView().controlSize(.small) }
                }
                if item.scope.requiresAdmin {
                    Label("System daemons need your administrator password to change.", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Stop unloads it until next login. Disable also keeps it from starting again. Enable reverses that.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                InfoGrid(rows: [
                    ("Runs at login", item.runAtLoad ? "Yes" : "No"),
                    ("Restarts if quit", item.keepAlive ? "Yes" : "No"),
                    ("Interval", item.startInterval.map { "every \($0)s" } ?? "—"),
                ])
                PathField(title: "Property list", path: item.plistPath)
                if let executable = item.executable { PathField(title: "Program", path: executable) }
                if item.arguments.count > 1 {
                    Text(item.arguments.joined(separator: " "))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(16)
        }
    }
}
