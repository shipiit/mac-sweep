import MacSweepCore
import SwiftUI

struct RecommendationsPanel: View {
    @Bindable var cleanup: CleanupModel
    @State private var showsConfirm = false
    @State private var copied = false

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Recommendations", subtitle: "Select items to clean. Nothing is selected for you.")
                    .padding(16)
                Divider()
                content
                Divider()
                footer.padding(14)
            }
        }
        .sheet(isPresented: $showsConfirm) {
            CleanConfirmSheet(cleanup: cleanup)
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
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(cleanup.selected.isEmpty ? "Nothing selected" : "\(Format.bytes(cleanup.selectedSize)) selected")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText())
                Text("\(cleanup.selectedItemCount) groups · \(cleanup.selectedTargets.count) locations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if cleanup.selected.isEmpty {
                Button("Select Safe") { withAnimation { cleanup.selectSafe() } }
                    .disabled(cleanup.items(.safe).isEmpty)
            } else {
                Button("Clear") { withAnimation { cleanup.clearSelection() } }
            }
            Button("Copy Script", systemImage: "doc.on.clipboard") {
                FileActions.copy(CleanupScript.make(cleanup.selectedTargets, home: cleanup.home))
                copied = true
            }
            .labelStyle(.iconOnly)
            .disabled(cleanup.selected.isEmpty)
            .help(copied ? "Copied" : "Copy the selection as a shell script to review and run yourself")
            Button("Clean…") { showsConfirm = true }
                .buttonStyle(.borderedProminent)
                .disabled(cleanup.selected.isEmpty || cleanup.isCleaning)
                .keyboardShortcut(.delete, modifiers: .command)
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
