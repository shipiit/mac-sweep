import AppKit
import MacSweepCore
import SwiftUI

/// Apps with their helpers rolled up, Activity-Monitor-plus style: one row per app, expandable.
struct GroupedProcessList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appAccent) private var accent
    let rows: [ProcessRow]
    @Binding var selection: Int32?
    let onKill: (KillRequest) -> Void
    @State private var expanded = Set<String>()

    var body: some View {
        let groups = ProcessGroups.group(processes: rows.map(\.snapshot), apps: runningApps)
        let cpuByPid = Dictionary(rows.map { ($0.pid, $0.cpu) }, uniquingKeysWith: { first, _ in first })
        let growing = Set(rows.filter(\.trend.isSteadilyGrowing).map(\.pid))
        let topMemory = Double(max(groups.first?.memory ?? 1, 1))
        List {
            ForEach(groups) { group in
                let cpu = group.processes.reduce(0) { $0 + (cpuByPid[$1.pid] ?? 0) }
                VStack(spacing: 0) {
                    groupRow(group, cpu: cpu, topMemory: topMemory, isGrowing: group.processes.contains { growing.contains($0.pid) })
                    if expanded.contains(group.id) {
                        ForEach(group.processes, id: \.pid) { process in
                            childRow(process, cpu: cpuByPid[process.pid] ?? 0, isGrowing: growing.contains(process.pid))
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func groupRow(_ group: ProcessGroup, cpu: Double, topMemory: Double, isGrowing: Bool) -> some View {
        HStack(spacing: 12) {
            Button { withAnimation(.snappy) { toggle(group.id) } } label: {
                Image(systemName: "chevron.right").rotationEffect(.degrees(expanded.contains(group.id) ? 90 : 0))
                    .foregroundStyle(.secondary).frame(width: 14)
            }
            .buttonStyle(.plain)
            .opacity(group.processes.count > 1 ? 1 : 0)
            .accessibilityLabel(expanded.contains(group.id) ? "Collapse \(group.name)" : "Expand \(group.name)")
            iconView(group)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.name).fontWeight(.medium).lineLimit(1)
                    if isGrowing {
                        Label("Growing", systemImage: "chart.line.uptrend.xyaxis").labelStyle(.iconOnly).foregroundStyle(.orange)
                    }
                }
                Text(group.processes.count == 1 ? "1 process" : "\(group.processes.count) processes · \(group.threads) threads")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 260, alignment: .leading)
            bar(value: Double(group.memory) / topMemory, label: Format.bytes(group.memory), color: accent)
            bar(value: min(cpu / 100, 1), label: Format.percent(cpu) + "%", color: cpu > 80 ? .orange : .teal)
                .frame(width: 140)
            Button(group.kind == .named && group.processes.count > 1 ? "Quit All" : "Quit") { quit(group) }
                .controlSize(.small)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { selection = group.processes.first?.pid }
    }

    private func childRow(_ process: ProcessSnapshot, cpu: Double, isGrowing: Bool) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 48)
            Text(process.name).font(.callout).lineLimit(1)
            if isGrowing { Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.orange).accessibilityLabel("Growing") }
            Spacer()
            Text("PID \(process.pid)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            Text(Format.bytes(process.memory)).font(.callout.monospacedDigit()).frame(width: 80, alignment: .trailing)
            Text(Format.percent(cpu) + "%").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
            Button { onKill(KillRequest(pid: process.pid, name: process.name, force: false)) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless).help("Quit \(process.name)").accessibilityLabel("Quit \(process.name)")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { selection = process.pid }
        .background(selection == process.pid ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private func iconView(_ group: ProcessGroup) -> some View {
        if let path = group.iconPath {
            FileIcon(path: path, size: 28)
        } else {
            Image(systemName: "gearshape.2").frame(width: 28, height: 28).foregroundStyle(.secondary)
        }
    }

    private func bar(value: Double, label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color).frame(width: max(proxy.size.width * min(max(value, 0), 1), 3))
                }
            }
            .frame(height: 6)
            Text(label).font(.callout.monospacedDigit()).frame(width: 72, alignment: .trailing)
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Apps quit the normal way (like ⌘Q); name groups get SIGTERM per process through the usual kill flow.
    private func quit(_ group: ProcessGroup) {
        switch group.kind {
        case .app(_, let pid):
            NSRunningApplication(processIdentifier: pid)?.terminate()
        case .named:
            for process in group.processes { onKill(KillRequest(pid: process.pid, name: process.name, force: false)) }
        }
    }

    private var runningApps: [RunningAppSnapshot] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .map { RunningAppSnapshot(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier ?? "", name: $0.localizedName ?? "",
                                      bundlePath: $0.bundleURL?.path, launchDate: $0.launchDate, lastActive: nil, isFrontmost: false) }
    }
}
