import MacSweepCore
import SwiftUI

struct MemoryOverview: View {
    let stats: SystemMemoryStats
    @State private var isPurging = false
    @State private var purgeError: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Memory").font(.headline)
                        Text("\(Format.memory(stats.used)) used of \(Format.memory(stats.total))")
                            .font(.system(.title2, design: .monospaced).weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: pressureSymbol).foregroundStyle(stats.pressure.color)
                            Text("Pressure: \(stats.pressure.rawValue)")
                        }
                        .font(.callout.weight(.medium))
                        Text("Swap \(Format.memory(stats.swapUsed)) of \(Format.memory(stats.swapTotal))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button { purge() } label: {
                        if isPurging { ProgressView().controlSize(.small) } else { Label("Purge", systemImage: "wind") }
                    }
                    .disabled(isPurging)
                    .help("Run `purge` as administrator to flush disk caches. Rarely needed; macOS manages this itself.")
                    .padding(.leading, 8)
                }
                StackedBar(segments: [
                    BarSegment(label: "App", value: Double(stats.app), color: .blue, detail: Format.memory(stats.app)),
                    BarSegment(label: "Wired", value: Double(stats.wired), color: .orange, detail: Format.memory(stats.wired)),
                    BarSegment(label: "Compressed", value: Double(stats.compressed), color: .purple, detail: Format.memory(stats.compressed)),
                    BarSegment(label: "Cached files", value: Double(stats.cached), color: .teal, detail: Format.memory(stats.cached)),
                    BarSegment(label: "Free", value: Double(stats.free), color: Color(nsColor: .quaternaryLabelColor), detail: Format.memory(stats.free)),
                ])
            }
        }
        .alert("Purge failed", isPresented: isPresented($purgeError), presenting: purgeError) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private var pressureSymbol: String {
        switch stats.pressure {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }

    private func purge() {
        isPurging = true
        Task {
            defer { isPurging = false }
            do {
                try await AdminRunner.purgeMemory()
            } catch AdminRunner.AdminError.cancelled {
                return
            } catch {
                purgeError = error.localizedDescription
            }
        }
    }
}
