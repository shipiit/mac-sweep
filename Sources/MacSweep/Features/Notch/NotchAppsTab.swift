import MacSweepCore
import SwiftUI

/// Top memory and top CPU side by side, each row with the app icon, value and a quit button.
struct NotchAppsTab: View {
    @Environment(AppModel.self) private var app
    let onQuit: (Int32, String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            column("Top Memory", rows: app.processes.rows.sorted { $0.memory > $1.memory }) { Format.bytes($0.snapshot.memory) }
            column("Top CPU", rows: app.processes.rows.sorted { $0.cpu > $1.cpu }) { Format.percent($0.cpu) + "%" }
        }
    }

    private func column(_ title: String, rows: [ProcessRow], value: @escaping (ProcessRow) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    app.section = .processes
                    app.openMainWindow?()
                } label: { Label("View All", systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle()) }
                    .buttonStyle(.plain).foregroundStyle(.cyan).font(.caption.weight(.semibold))
            }
            .padding(.bottom, 4)
            ForEach(rows.prefix(7)) { row in
                HStack(spacing: 10) {
                    ProcessIcon(pid: row.pid, path: row.snapshot.path, size: 20)
                    Text(row.name).lineLimit(1)
                    if row.trend.isSteadilyGrowing {
                        Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.orange).accessibilityLabel("Memory growing")
                    }
                    Spacer(minLength: 4)
                    Text(value(row)).monospacedDigit().foregroundStyle(.white.opacity(0.75))
                    InlineConfirmButton(help: "Quit \(row.name)") { onQuit(row.pid, row.name) }
                }
                .font(.system(size: 13))
                .padding(.vertical, 3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
