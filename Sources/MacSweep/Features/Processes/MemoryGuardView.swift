import MacSweepCore
import SwiftUI

/// Memory Guard settings plus "what's using your memory", ranked, with idle and growing flags.
struct MemoryGuardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appAccent) private var accent

    var body: some View {
        @Bindable var guardian = app.memoryGuard
        let memory = app.processes.memory
        let groups = app.processes.rows.reduce(into: [String: (UInt64, Bool)]()) { result, row in
            let key = row.name
            let current = result[key] ?? (0, false)
            result[key] = (current.0 + row.memory, current.1 || row.trend.isSteadilyGrowing)
        }
        let top = groups.sorted { $0.value.0 > $1.value.0 }.prefix(12)
        let idle = guardian.idleApps(app)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Panel(padding: 22) {
                    HStack(spacing: 24) {
                        RingGauge(value: memory.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0, label: "Memory",
                                  caption: memory.map { "Pressure: \($0.pressure.rawValue)" }, size: 96, lineWidth: 10)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Memory Guard").font(.system(size: 26, weight: .bold))
                            Text("When memory stays under pressure for a minute, MacSweep tells you which idle apps use the most, or quits them for you (politely, like ⌘Q, so unsaved work can still be saved). The app you're using and system apps are never touched.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 16) {
                                Picker("When memory is low", selection: $guardian.mode) { ForEach(MemoryGuardMode.allCases) { Text($0.rawValue).tag($0) } }
                                    .pickerStyle(.segmented).fixedSize()
                                Picker("Idle for", selection: $guardian.idleMinutes) {
                                    ForEach([15, 30, 60, 120], id: \.self) { Text("Idle \($0 < 60 ? "\($0) min" : "\($0 / 60) h")").tag($0) }
                                }
                                .fixedSize()
                            }
                        }
                    }
                }
                StatStrip {
                    StatTile(title: "Used", value: Format.bytes(memory?.used ?? 0), detail: "of \(Format.bytes(memory?.total ?? 0))")
                    StatTile(title: "Swap", value: Format.bytes(memory?.swapUsed ?? 0), detail: "written to disk", dot: (memory?.swapUsed ?? 0) > 2 << 30 ? .orange : nil)
                    StatTile(title: "Idle apps", value: "\(idle.count)", detail: Format.bytes(idle.reduce(0) { $0 + $1.memory }) + " could be freed")
                }
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's using your memory").font(.title3.weight(.semibold))
                        let largest = Double(max(top.first?.value.0 ?? 1, 1))
                        ForEach(Array(top), id: \.key) { name, value in
                            HStack(spacing: 10) {
                                Text(name).lineLimit(1).frame(width: 220, alignment: .leading)
                                GeometryReader { proxy in
                                    Capsule().fill(accent.opacity(0.7)).frame(width: max(proxy.size.width * Double(value.0) / largest, 3))
                                }
                                .frame(height: 8)
                                if value.1 { Label("Growing", systemImage: "chart.line.uptrend.xyaxis").font(.caption).foregroundStyle(.orange) }
                                if idle.contains(where: { $0.app.name == name }) { Label("Idle", systemImage: "moon.zzz").font(.caption).foregroundStyle(.secondary) }
                                Text(Format.bytes(value.0)).monospacedDigit().frame(width: 80, alignment: .trailing)
                            }
                        }
                    }
                }
                if !idle.isEmpty {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Idle apps you could quit").font(.title3.weight(.semibold))
                            ForEach(idle) { item in
                                HStack {
                                    FileIcon(path: item.app.bundlePath ?? "", size: 24)
                                    Text(item.app.name)
                                    Text("unused for \(Uptime.formatted(Date().timeIntervalSince(item.idleSince)))\(item.isAtLeast ? "+" : "")").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(Format.bytes(item.memory)).monospacedDigit()
                                    Button("Quit") { NSRunningApplication(processIdentifier: item.app.pid)?.terminate() }.controlSize(.small)
                                }
                            }
                        }
                    }
                }
                if !guardian.events.isEmpty {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent actions").font(.title3.weight(.semibold))
                            ForEach(guardian.events) { ActivityRow(symbol: "memorychip", tint: .orange, title: $0.text, detail: "", date: $0.date) }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Memory Guard")
    }
}
