import Charts
import MacSweepCore
import SwiftUI

struct ProcessDetails: Equatable {
    var arguments: [String]?
    var workingDirectory: String?
}

struct ProcessInspector: View {
    let row: ProcessRow
    let samples: [MemorySample]
    let ports: [ListeningPort]
    let onKill: (KillRequest) -> Void

    @State private var details = ProcessDetails()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ProcessIcon(pid: row.pid, path: row.snapshot.path, size: 36)
                    VStack(alignment: .leading) {
                        Text(row.name).font(.title3.weight(.semibold)).lineLimit(2)
                        Text("PID \(row.pid) · parent \(row.snapshot.ppid) · \(row.user)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Quit") { onKill(KillRequest(pid: row.pid, name: row.name, force: false)) }
                    Button("Force Kill", role: .destructive) { onKill(KillRequest(pid: row.pid, name: row.name, force: true)) }
                    Spacer()
                }

                memoryChart

                if row.trend.isSteadilyGrowing {
                    Label("Memory grew \(Format.signedBytes(row.trend.growth)) while being watched, about \(Format.signedBytes(Int64(row.trend.bytesPerMinute)))/min. That can mean a leak, or a cache warming up. If it keeps climbing, restart it.", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                InfoGrid(rows: [
                    ("Memory", Format.bytes(row.snapshot.memory)),
                    ("CPU", Format.percent(row.cpu) + " %"),
                    ("Threads", row.snapshot.threads.map(String.init) ?? "—"),
                    ("Started", row.snapshot.started.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—"),
                ])

                if let path = row.snapshot.path {
                    PathField(title: "Executable", path: path)
                }
                if let cwd = details.workingDirectory {
                    PathField(title: "Working directory", path: cwd)
                }
                if let arguments = details.arguments, !arguments.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Command line").font(.caption).foregroundStyle(.secondary)
                        Text(arguments.joined(separator: " "))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                if !ports.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Listening on").font(.caption).foregroundStyle(.secondary)
                        ForEach(ports) { port in
                            Text("\(port.proto) \(port.port)  \(port.addresses.joined(separator: ", "))")
                                .font(.system(.callout, design: .monospaced))
                        }
                    }
                }
                if row.snapshot.memory == nil {
                    Label("Owned by another user. Memory details need administrator rights.", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .task(id: row.pid) { details = await Self.loadDetails(pid: row.pid) }
    }

    static func loadDetails(pid: Int32) async -> ProcessDetails {
        await Task.detached(priority: .userInitiated) {
            ProcessDetails(arguments: ProcArgs.arguments(pid: pid), workingDirectory: ProcReader.workingDirectory(pid))
        }.value
    }

    @ViewBuilder private var memoryChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Memory over time").font(.caption).foregroundStyle(.secondary)
            if samples.count < 2 {
                Text("Collecting samples…").font(.callout).foregroundStyle(.tertiary).frame(height: 110)
            } else {
                Chart(samples, id: \.time) { sample in
                    AreaMark(x: .value("Seconds", sample.time), y: .value("Memory", Double(sample.bytes) / 1_048_576))
                        .foregroundStyle(chartColor.opacity(0.18))
                    LineMark(x: .value("Seconds", sample.time), y: .value("Memory", Double(sample.bytes) / 1_048_576))
                        .foregroundStyle(chartColor)
                }
                .chartXAxis(.hidden)
                .chartYAxisLabel("MB")
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 110)
                .accessibilityLabel("Memory history, latest \(Format.bytes(samples.last?.bytes))")
            }
        }
    }

    private var chartColor: Color { row.trend.isSteadilyGrowing ? .orange : .blue }
}

struct InfoGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(rows, id: \.0) { title, value in
                GridRow {
                    Text(title).foregroundStyle(.secondary)
                    Text(value).monospacedDigit().textSelection(.enabled)
                }
            }
        }
        .font(.callout)
    }
}

struct PathField: View {
    let title: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                Text(Format.path(path))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                Spacer()
                Button { FileActions.reveal(path) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                    .accessibilityLabel("Reveal \(title) in Finder")
            }
        }
    }
}
