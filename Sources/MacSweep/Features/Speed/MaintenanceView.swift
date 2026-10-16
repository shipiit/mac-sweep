import MacSweepCore
import SwiftUI

/// Upkeep jobs as one tidy list: what each fixes, whether it needs a password, and its last result.
struct MaintenanceView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appAccent) private var accent

    private var recommended: [MaintenanceTask] { MaintenanceTask.allCases.filter { !$0.requiresAdmin } }

    var body: some View {
        let model = app.maintenance
        let isBusy = MaintenanceTask.allCases.contains { model.status(of: $0) == .running }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 18) {
                    Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 60, height: 60).background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keep macOS running smoothly").font(.title2.weight(.semibold))
                        Text("Run these when something feels off. None of them deletes your files.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { for task in recommended { await model.run(task) } }
                    } label: {
                        Label("Run Recommended", systemImage: "play.fill").padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(isBusy)
                    .help("Runs every task that doesn't need your password")
                }
                VStack(spacing: 0) {
                    ForEach(MaintenanceTask.allCases) { task in
                        MaintenanceRow(task: task, status: model.status(of: task), isDisabled: isBusy) { Task { await model.run(task) } }
                        if task != MaintenanceTask.allCases.last { Divider().padding(.leading, 66) }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Maintenance")
    }
}

private struct MaintenanceRow: View {
    let task: MaintenanceTask
    let status: MaintenanceModel.Status
    let isDisabled: Bool
    let run: () -> Void
    @Environment(\.appAccent) private var accent

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: task.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                .frame(width: 38, height: 38).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title).fontWeight(.semibold)
                    if task.requiresAdmin { Pill(text: "Password", color: .orange) }
                }
                Text(task.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            statusView
            Button(status == .running ? "Running…" : "Run", action: run)
                .disabled(isDisabled)
                .frame(minWidth: 70)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .idle: EmptyView()
        case .running: ProgressView().controlSize(.small)
        case .done(let date):
            Label("Done \(Format.relative(date))", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Label("Failed", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).help(message)
        }
    }
}
