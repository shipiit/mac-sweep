import MacSweepCore
import SwiftUI

/// Leftover Chrome / Brave / Edge app copies in the temp area.
struct BrowserCopiesCard: View {
    let model: HiddenSpaceModel
    @State private var confirming = false

    var body: some View {
        let running = model.runningBrowsers()
        let blocked = Set(model.clones.map(\.bundleID)).filter(running.contains)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    SectionHeader(title: "Browser code-sign copies",
                                  subtitle: "Chromium browsers copy themselves here at launch and leave the copy behind after a crash, force-quit or restart. They're throwaway: the browser makes a fresh one next time.")
                    Spacer()
                    Button("Delete \(model.clones.count) Copies") { confirming = true }
                        .disabled(model.clones.isEmpty || model.busy != nil || !blocked.isEmpty)
                }
                if model.clones.isEmpty {
                    Label("No leftover copies.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    let byBrowser = Dictionary(grouping: model.clones, by: \.bundleID)
                    ForEach(byBrowser.keys.sorted(), id: \.self) { id in
                        let clones = byBrowser[id] ?? []
                        HStack {
                            Text(id).font(.callout.monospaced())
                            if running.contains(id) { Text("Running — quit it first").font(.caption).foregroundStyle(.orange) }
                            Spacer()
                            Text("\(clones.count) copies · up to \(Format.bytes(clones.reduce(0) { $0 + $1.size }))").font(.callout.monospacedDigit())
                        }
                    }
                    Text("Copies of the same browser version share disk blocks, so the space you get back is often smaller than the total shown.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Delete \(model.clones.count) browser copies?", isPresented: $confirming) {
            Button("Delete Copies", role: .destructive) { Task { await model.removeClones() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They're deleted right away (not moved to the Trash) because they are temporary copies of the browser app itself.")
        }
    }
}

/// Installed iOS / watchOS / visionOS simulator runtimes.
struct RuntimesCard: View {
    let model: HiddenSpaceModel
    @State private var pending: SimulatorRuntime?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Simulator runtimes", subtitle: "Each runtime is a disk image outside your home folder. Xcode downloads one again if a project needs it.")
                if model.runtimes.isEmpty {
                    Label("No simulator runtimes installed.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                ForEach(model.runtimes) { runtime in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(runtime.name).font(.callout.weight(.semibold))
                            Text(runtime.lastUsed.map { "Last used \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Never used")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.bytes(runtime.size)).font(.callout.monospacedDigit())
                        Button("Delete") { pending = runtime }.disabled(!runtime.isDeletable || model.busy != nil)
                    }
                }
            }
        }
        .confirmationDialog("Delete \(pending?.name ?? "runtime")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            presenting: pending) { runtime in
            Button("Delete Runtime", role: .destructive) { Task { await model.deleteRuntime(runtime) } }
            Button("Cancel", role: .cancel) {}
        } message: { runtime in
            Text("Frees about \(Format.bytes(runtime.size)). Simulators using it stop working until Xcode downloads it again.")
        }
    }
}
