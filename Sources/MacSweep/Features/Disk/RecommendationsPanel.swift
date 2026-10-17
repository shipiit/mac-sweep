import MacSweepCore
import SwiftUI

struct RecommendationsPanel: View {
    @Bindable var cleanup: CleanupModel
    /// The folder selected (or open) in the treemap; the Folder tab lists its contents to tick.
    let folder: FileNode?
    @State private var showsConfirm = false
    @State private var showsScript = false
    @State private var tab: Tab = .recommendations

    enum Tab: String, CaseIterable, Identifiable {
        case recommendations = "Recommendations", folder = "Folder"
        var id: String { rawValue }
    }

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Panel", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden()
                    Text(tab == .recommendations ? "Known caches and build output. Nothing is selected for you."
                         : "Tick anything inside \(folder?.name ?? "the selected folder"). Picks from different folders add up below.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                Divider()
                if tab == .recommendations { content } else { FolderPicker(folder: folder, cleanup: cleanup) }
                Divider()
                footer.padding(14)
            }
        }
        .sheet(isPresented: $showsConfirm) {
            CleanConfirmSheet(cleanup: cleanup)
        }
        .sheet(isPresented: $showsScript) {
            CleanupScriptSheet(script: CleanupScript.make(cleanup.selectedTargets, home: cleanup.home, reviewFirst: cleanup.reviewPaths))
        }
        .onChange(of: folder?.path) { _, path in
            if path != nil, folder?.path != cleanup.home { tab = .folder }
        }
        .alert(
            reportTitle,
            isPresented: isPresented($cleanup.report),
            presenting: cleanup.report
        ) { _ in
            if cleanup.report?.mode == .trash {
                Button("Open Trash") { FileActions.open(NSHomeDirectory() + "/.Trash") }
            }
            Button("Done", role: .cancel) {}
        } message: { report in
            Text(reportMessage(report))
        }
    }

    @ViewBuilder private var content: some View {
        if cleanup.isEvaluating && cleanup.items.isEmpty {
            ProgressView("Matching cleanup rules…").frame(maxWidth: .infinity, minHeight: 200)
        } else if cleanup.items.isEmpty {
            ContentUnavailableView(
                "Nothing to clean",
                systemImage: "sparkles",
                description: Text("No known caches or build output were found in the scanned folder.")
            )
            .frame(minHeight: 200)
        } else {
            List {
                ForEach(CleanupSafety.allCases, id: \.self) { safety in
                    let items = cleanup.items(safety)
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { RecommendationRow(item: $0, cleanup: cleanup) }
                        } header: {
                            HStack {
                                Pill(text: safety.title, color: safety.color)
                                Spacer()
                                Text(Format.bytes(cleanup.total(safety))).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(cleanup.hasSelection ? "\(Format.bytes(cleanup.selectedSize)) selected" : "Nothing selected")
                    .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                Spacer()
                Text("\(cleanup.selectedTargets.count) locations").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if cleanup.hasSelection {
                    Button("Clear") { cleanup.clearSelection() }
                } else {
                    Button("Select Safe") { cleanup.selectSafe() }.disabled(cleanup.items(.safe).isEmpty)
                }
                Button { showsScript = true } label: { Label("Script", systemImage: "terminal") }
                    .disabled(!cleanup.hasSelection)
                    .help("See a cleanup script that uses each tool's own clean command; nothing is deleted")
                Spacer(minLength: 0)
                Button { showsConfirm = true } label: { Label("Clean…", systemImage: "trash").frame(minWidth: 70) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!cleanup.hasSelection || cleanup.isCleaning)
                    .keyboardShortcut(.delete, modifiers: .command)
            }
            .controlSize(.regular)
        }
    }

    private var reportTitle: String {
        guard let report = cleanup.report else { return "" }
        return report.failures.isEmpty ? "Cleaned \(Format.bytes(report.freed))" : "Cleaned with \(report.failures.count) problems"
    }

    private func reportMessage(_ report: CleanupModel.Report) -> String {
        var lines = ["\(report.removedCount) locations removed."]
        if report.mode == .trash {
            lines.append("They're in the Trash. Empty it to get the space back.")
        }
        for failure in report.failures.prefix(5) {
            switch failure.outcome {
            case .refused(let reason), .failed(let reason): lines.append("• \(Format.path(failure.path)): \(reason)")
            case .removed: continue
            }
        }
        return lines.joined(separator: "\n")
    }
}
