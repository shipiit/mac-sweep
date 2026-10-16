import MacSweepCore
import SwiftUI

struct PortsView: View {
    @Environment(AppModel.self) private var app
    @State private var search = ""
    @State private var killRequest: KillRequest?
    @State private var copied: String?

    var body: some View {
        @Bindable var ports = app.ports
        let visible = ports.ports.filter { port in
            let query = search.lowercased()
            guard !query.isEmpty else { return true }
            let detail = ports.details[port.pid]
            return String(port.port).hasPrefix(query) || String(port.pid) == query || port.command.lowercased().contains(query)
                || (detail?.location?.lowercased().contains(query) ?? false) || (detail?.summary?.lowercased().contains(query) ?? false)
        }
        let grouped = Dictionary(grouping: visible) { PortDescriber.category(command: $0.command, executable: ports.details[$0.pid]?.executable) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary(ports.ports)
                if let error = ports.error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                if visible.isEmpty && !ports.isLoading {
                    ContentUnavailableView(search.isEmpty ? "Nothing is listening" : "No matches", systemImage: "network.slash")
                }
                ForEach(PortCategory.allCases) { category in
                    if let items = grouped[category], !items.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(category.rawValue) · \(items.count)").font(.headline).padding(.leading, 4)
                            VStack(spacing: 0) {
                                ForEach(items) { port in
                                    PortRow(port: port, details: ports.details[port.pid], process: app.processes.row(pid: port.pid),
                                            copied: $copied) { killRequest = $0 }
                                    if port.id != items.last?.id { Divider().padding(.leading, 90) }
                                }
                            }
                            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5)))
                        }
                    }
                }
                if !ports.includesSystem {
                    Label("Showing your own processes. Turn on Include system to also see ports owned by macOS and other users.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle("Ports")
        .navigationSubtitle("\(ports.ports.count) listening · updated \(Format.relative(ports.lastUpdated))")
        .searchable(text: $search, prompt: "Port, process, folder or command")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle("UDP", isOn: $ports.includeUDP)
                    .onChange(of: ports.includeUDP) { Task { await ports.refresh() } }
                Toggle("Include system", isOn: Binding(get: { ports.includesSystem }, set: { value in Task { await ports.setIncludesSystem(value) } }))
                    .help("Uses lsof as administrator")
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await ports.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(ports.isLoading)
            }
        }
        .killFlow($killRequest) {
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                await ports.refresh()
            }
        }
        .task {
            while !Task.isCancelled {
                await ports.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func summary(_ ports: [ListeningPort]) -> some View {
        let exposed = ports.filter { !$0.isLocalOnly }.count
        return StatStrip {
            StatTile(title: "Listening", value: "\(ports.count)", detail: "ports")
            StatTile(title: "Reachable from network", value: "\(exposed)", detail: exposed == 0 ? "all local" : "check these", dot: exposed > 0 ? .orange : .green)
            StatTile(title: "This Mac only", value: "\(ports.count - exposed)", detail: "loopback", dot: .green)
            StatTile(title: "Processes", value: "\(Set(ports.map(\.pid)).count)", detail: "owning ports")
        }
    }
}

private struct PortRow: View {
    let port: ListeningPort
    let details: PortProcessDetails?
    let process: ProcessRow?
    @Binding var copied: String?
    let onKill: (KillRequest) -> Void
    @Environment(\.appAccent) private var accent

    var body: some View {
        let url = "http://localhost:\(port.port)"
        HStack(alignment: .center, spacing: 14) {
            Text(":\(port.port)")
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(width: 76, alignment: .leading)
            ProcessIcon(pid: port.pid, path: details?.executable, size: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(process?.name ?? port.command).fontWeight(.semibold)
                    Text("PID \(port.pid)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    exposure
                }
                if let summary = details?.summary {
                    Text(summary).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                }
                if let location = details?.location {
                    Button { FileActions.reveal(location) } label: {
                        Label(Format.path(location), systemImage: "folder").font(.caption).lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.link)
                    .help("Reveal the folder this server runs from")
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.bytes(process?.snapshot.memory)).font(.callout.monospacedDigit())
                if let started = process?.snapshot.started {
                    Text("up \(Uptime.formatted(Date().timeIntervalSince(started)))").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 90, alignment: .trailing)
            HStack(spacing: 6) {
                if port.proto == "TCP" {
                    Button { FileActions.open(url: URL(string: url)) } label: { Image(systemName: "safari") }
                        .help("Open \(url)").accessibilityLabel("Open \(url)")
                    Button {
                        FileActions.copy(url)
                        copied = port.id
                    } label: { Image(systemName: copied == port.id ? "checkmark" : "link") }
                        .help("Copy \(url)").accessibilityLabel("Copy \(url)")
                }
                Button { onKill(KillRequest(pid: port.pid, name: port.command, force: false)) } label: { Image(systemName: "stop.circle") }
                    .help("Stop \(port.command)").accessibilityLabel("Stop \(port.command)")
            }
            .buttonStyle(.borderless)
            .font(.title3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contextMenu {
            Button("Copy Port") { FileActions.copy(String(port.port)) }
            if let summary = details?.arguments.joined(separator: " ") { Button("Copy Full Command") { FileActions.copy(summary) } }
            if let executable = details?.executable { Button("Reveal Executable") { FileActions.reveal(executable) } }
            Divider()
            Button("Force Kill") { onKill(KillRequest(pid: port.pid, name: port.command, force: true)) }
        }
    }

    @ViewBuilder private var exposure: some View {
        if port.isLocalOnly {
            Label("This Mac", systemImage: "lock.fill").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                .padding(.horizontal, 6).padding(.vertical, 1).background(Color.green.opacity(0.12), in: Capsule())
        } else {
            Label("Network · \(port.addresses.joined(separator: ", "))", systemImage: "globe").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                .padding(.horizontal, 6).padding(.vertical, 1).background(Color.orange.opacity(0.12), in: Capsule())
        }
    }
}
