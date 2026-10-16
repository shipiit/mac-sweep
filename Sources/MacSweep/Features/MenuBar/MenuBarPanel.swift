import Darwin
import MacSweepCore
import SwiftUI

struct MenuBarLabel: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKeys.menuBarStyle) private var style: MenuBarStyle = .cpuAndMemory

    var body: some View {
        let memory = app.processes.memory.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0
        Image(nsImage: MenuBarGlyph.image(cpu: app.monitor.cpu, memory: memory, style: style))
        .onAppear {
            app.openMainWindow = {
                openWindow(id: "main")
                NSApp.activate()
            }
        }
    }
}

struct MenuBarPanel: View {
    @Environment(\.appAccent) private var accent
    @Environment(AppModel.self) private var app
    @AppStorage("showNotchHUD") private var showNotchHUD = true
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            MenuBarTileGrid(open: open)
            processList
            if !app.ports.ports.isEmpty { portList }
            if let feedback {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 400)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("MacSweep").font(.headline)
                Text(Host.current().localizedName ?? "This Mac").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let pressure = app.processes.memory?.pressure {
                Pill(text: "Memory \(pressure.rawValue.lowercased())", color: pressure.color)
            }
        }
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top memory").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(app.processes.rows.sorted { $0.memory > $1.memory }.prefix(4)) { row in
                HStack(spacing: 8) {
                    ProcessIcon(pid: row.pid, path: row.snapshot.path)
                    Text(row.name).lineLimit(1)
                    if row.trend.isSteadilyGrowing {
                        Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.orange).accessibilityLabel("Memory growing")
                    }
                    Spacer()
                    Text(Format.bytes(row.snapshot.memory)).monospacedDigit().foregroundStyle(.secondary)
                    InlineConfirmButton(help: "Quit \(row.name)") { quit(row.pid, row.name) }
                }
                .font(.callout)
            }
        }
    }

    private var portList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Listening ports").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if app.ports.ports.isEmpty {
                Text("None").font(.callout).foregroundStyle(.tertiary)
            }
            ForEach(app.ports.ports.prefix(4)) { port in
                HStack(spacing: 8) {
                    Text(":\(port.port)").font(.system(.callout, design: .monospaced).weight(.semibold)).frame(width: 60, alignment: .leading)
                    Text(port.command).lineLimit(1)
                    Image(systemName: port.isLocalOnly ? "lock.fill" : "globe")
                        .foregroundStyle(port.isLocalOnly ? .green : .orange)
                        .help(port.isLocalOnly ? "This Mac only" : "Reachable from the network")
                    Spacer()
                    if port.proto == "TCP" {
                        Button { FileActions.open(url: URL(string: "http://localhost:\(port.port)")) } label: {
                            Image(systemName: "safari")
                        }
                        .buttonStyle(.plain)
                        .help("Open http://localhost:\(port.port)")
                        .accessibilityLabel("Open port \(port.port) in browser")
                    }
                    InlineConfirmButton(help: "Stop \(port.command) on port \(port.port)") { quit(port.pid, port.command) }
                }
                .font(.callout)
            }
            if app.ports.ports.count > 4 {
                Button("All \(app.ports.ports.count) ports…") { open(.ports) }.buttonStyle(.link).font(.caption)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open MacSweep") { open(.overview) }
                .keyboardShortcut("o")
            Toggle("Notch", isOn: $showNotchHUD)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Show live stats around the notch")
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func open(_ section: SidebarSection) {
        app.section = section
        app.openMainWindow?()
    }

    private func quit(_ pid: Int32, _ name: String) {
        switch ProcessKiller.send(SIGTERM, to: pid, name: name) {
        case .sent, .notFound: feedback = "Asked \(name) to quit."
        case .notPermitted: feedback = "\(name) belongs to another user. Use Processes to kill it as administrator."
        case .refused(let reason): feedback = reason
        case .failed(let code): feedback = String(cString: strerror(code))
        }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await app.processes.refresh()
            await app.ports.refresh()
        }
    }
}
