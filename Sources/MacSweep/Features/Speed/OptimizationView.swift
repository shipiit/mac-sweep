import Darwin
import MacSweepCore
import SwiftUI

extension Advice.Impact {
    var color: Color {
        switch self {
        case .high: .red
        case .medium: .orange
        case .low: .blue
        }
    }

    var title: String {
        switch self {
        case .high: "High impact"
        case .medium: "Medium"
        case .low: "Tip"
        }
    }
}

extension AppModel {
    /// Snapshot of everything the advisor needs, taken from the live models.
    var advisorInput: AdvisorInput {
        let heavy = processes.rows
            .filter { $0.trend.isSteadilyGrowing || $0.cpu >= 80 }
            .sorted { $0.memory > $1.memory }
            .prefix(5)
            .map { (pid: $0.pid, name: $0.name, memory: $0.memory, cpu: $0.cpu, growing: $0.trend.isSteadilyGrowing) }
        return AdvisorInput(
            memory: processes.memory,
            heavyProcesses: Array(heavy),
            loginItemCount: startup.items.filter { $0.runAtLoad && $0.scope != .daemon }.count,
            disk: monitor.volume,
            battery: system.battery,
            safeCleanupBytes: cleanup.total(.safe),
            trashBytes: disk.result?.root.node(at: home + "/.Trash")?.size ?? 0,
            protectionsOff: security.protections.filter { $0.state == .off }.map(\.title),
            securityFindings: security.highFindings,
            uptimeDays: Int(ProcessInfo.processInfo.systemUptime / 86_400),
            lastScan: disk.result?.finishedAt
        )
    }

    func perform(_ action: Advice.Action) {
        switch action {
        case .openStorage: section = .storage
        case .openStartup: section = .startup
        case .openSecurity: section = .security
        case .openProcesses: section = .processes
        case .openMaintenance: section = .maintenance
        case .scanDisk: disk.scan(root: home); section = .storage
        case .emptyTrash:
            let trash = disk.result?.root.node(at: home + "/.Trash")?.children.filter { $0.kind != .aggregate } ?? []
            cleanup.remove(trash.map { CleanupTarget(path: $0.path, size: $0.size) }, mode: .delete)
        case .quitProcess(let pid, let name):
            _ = ProcessKiller.send(SIGTERM, to: pid, name: name)
        case .none:
            break
        }
    }
}

struct OptimizationView: View {
    @Environment(\.appAccent) private var accent
    @Environment(AppModel.self) private var app
    @State private var confirmTrash = false

    var body: some View {
        let advice = Advisor.advise(app.advisorInput)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card {
                    HStack(spacing: 16) {
                        Image(systemName: advice.isEmpty ? "hare.fill" : "slider.horizontal.3")
                            .font(.system(size: 36))
                            .foregroundStyle(advice.isEmpty ? .green : accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(advice.isEmpty ? "Your Mac is running well" : "\(advice.count) ways to speed up your Mac")
                                .font(.title2.weight(.semibold))
                            Text("Based on live memory, CPU, disk, startup items, battery and security checks.").foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(advice) { item in
                    Card(padding: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(item.impact.color).frame(width: 9, height: 9).padding(.top, 6).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(item.title).fontWeight(.semibold)
                                    Pill(text: item.impact.title, color: item.impact.color)
                                }
                                Text(item.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if let title = item.actionTitle {
                                Button(title) {
                                    if item.action == .emptyTrash { confirmTrash = true } else { app.perform(item.action) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Optimization")
        .task { if app.startup.items.isEmpty { await app.startup.refresh() } }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmTrash, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) { app.perform(.emptyTrash) }
        } message: {
            Text("Items in the Trash are deleted permanently.")
        }
    }
}
