import AppKit
import MacSweepCore
import SwiftUI

/// Apps you haven't touched for a while that still hold memory, with a safe, normal quit.
struct IdleAppsPanel: View {
    @Environment(AppModel.self) private var app
    @AppStorage("idleThresholdMinutes") private var thresholdMinutes = 120
    @AppStorage("idleExcluded") private var excludedRaw = ""
    @State private var confirmQuitAll = false
    @State private var expanded = true
    @AppStorage(AutoQuitter.listKey) private var autoQuitRaw = ""

    private var autoQuit: Set<String> { Set(autoQuitRaw.split(separator: ",").map(String.init)) }

    private var excluded: Set<String> { Set(excludedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        let idle = IdleApps.find(
            apps: runningApps, processes: app.processes.rows.map(\.snapshot), watchingSince: app.usage.watchingSince,
            threshold: TimeInterval(thresholdMinutes * 60), excluded: excluded
        )
        let total = idle.reduce(0) { $0 + $1.memory }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(.indigo).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(idle.isEmpty ? "No idle apps" : "\(idle.count) idle apps are holding \(Format.memory(total))").font(.headline)
                        Text(autoQuit.isEmpty
                             ? "Apps you haven't used for a while. Nothing quits on its own; turn on Auto-quit per app in its ⋯ menu."
                             : "Auto-quit is on for \(autoQuit.count) app\(autoQuit.count == 1 ? "" : "s"); they quit normally after this idle time.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Idle for", selection: $thresholdMinutes) {
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("4 hours").tag(240)
                    }
                    .fixedSize()
                    if !idle.isEmpty {
                        Button("Quit All…") { confirmQuitAll = true }
                        Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                            Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 0 : -90))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(expanded ? "Collapse idle apps" : "Expand idle apps")
                    }
                }
                if expanded {
                    ForEach(idle) { row($0) }
                }
            }
        }
        .confirmationDialog("Quit \(idle.count) idle apps?", isPresented: $confirmQuitAll, titleVisibility: .visible) {
            Button("Quit All") { idle.forEach { quit($0) } }
        } message: {
            Text("Each app is asked to quit normally, so you'll be prompted to save any unsaved work. Frees about \(Format.memory(total)).")
        }
    }

    private func row(_ item: IdleApp) -> some View {
        HStack(spacing: 10) {
            if let path = item.app.bundlePath { FileIcon(path: path, size: 22) }
            Text(item.app.name).fontWeight(.medium)
            Text(idleText(item)).font(.caption).foregroundStyle(.secondary)
            if autoQuit.contains(item.app.bundleID) { Pill(text: "Auto-quit", color: .indigo) }
            Spacer()
            Text("\(item.processCount) processes").font(.caption).foregroundStyle(.tertiary)
            Text(Format.memory(item.memory)).monospacedDigit().fontWeight(.semibold).frame(width: 80, alignment: .trailing)
            Button("Quit") { quit(item) }
            Menu {
                Toggle("Auto-quit when idle", isOn: Binding(
                    get: { autoQuit.contains(item.app.bundleID) },
                    set: { AutoQuitter.setEnabled(item.app.bundleID, $0); autoQuitRaw = UserDefaults.standard.string(forKey: AutoQuitter.listKey) ?? "" }
                ))
                Button("Never suggest \(item.app.name)") { excludedRaw = (excluded.union([item.app.bundleID])).sorted().joined(separator: ",") }
                Button("Show in Processes") { app.section = .processes }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More options for \(item.app.name)")
        }
        .font(.callout)
    }

    private func idleText(_ item: IdleApp) -> String {
        let minutes = Int(Date().timeIntervalSince(item.idleSince) / 60)
        let amount = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        return item.isAtLeast ? "Not used for at least \(amount)" : "Last used \(amount) ago"
    }

    private var runningApps: [RunningAppSnapshot] {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .map { running in
                let id = running.bundleIdentifier ?? ""
                return RunningAppSnapshot(pid: running.processIdentifier, bundleID: id, name: running.localizedName ?? id,
                                          bundlePath: running.bundleURL?.path, launchDate: running.launchDate,
                                          lastActive: app.usage.lastActive[id], isFrontmost: running.processIdentifier == front)
            }
    }

    /// Normal quit (like ⌘Q), never a kill: apps get to ask about unsaved changes.
    private func quit(_ item: IdleApp) {
        NSRunningApplication(processIdentifier: item.app.pid)?.terminate()
        Task {
            try? await Task.sleep(for: .seconds(1))
            await app.processes.refresh()
        }
    }
}
