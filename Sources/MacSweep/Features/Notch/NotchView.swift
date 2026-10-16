import MacSweepCore
import SwiftUI

/// Black, notch-coloured surface: collapsed it shows two "ears" of live stats beside the camera,
/// expanded it drops down into a mini dashboard.
struct NotchView: View {
    let state: NotchState
    @Environment(AppModel.self) private var app

    var body: some View {
        let size = state.isExpanded ? NotchState.expandedSize : state.collapsedSize
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: state.isExpanded ? 26 : 10, bottomTrailingRadius: state.isExpanded ? 26 : 10, style: .continuous)
                    .fill(.black)
                    .shadow(color: .black.opacity(state.isExpanded ? 0.35 : 0), radius: 18, y: 6)
                if state.isExpanded {
                    NotchDashboard(topInset: state.notchSize.height)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    ears.transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            Spacer(minLength: 0)
        }
        .frame(width: NotchState.expandedSize.width, height: NotchState.expandedSize.height)
        .environment(\.colorScheme, .dark)
    }

    private var ears: some View {
        let memory = app.processes.memory.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0
        let tool = AIUsageModel.defaultTool
        let session = app.ai.limitLines(for: tool).first
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                EarStat(symbol: "cpu", value: app.monitor.cpu)
                EarStat(symbol: "memorychip", value: memory)
            }
            .frame(width: NotchState.earWidth)
            Spacer(minLength: state.notchSize.width)
            Group {
                if let session {
                    // Shows what's left, so low numbers are the warning: colour by the used share.
                    EarStat(symbol: "flame", value: 1 - session.left, shown: session.left,
                            help: "\(session.title): \(Int((session.left * 100).rounded()))% left")
                } else {
                    EarStat(symbol: "memorychip", value: memory)
                }
            }
            .frame(width: NotchState.earWidth)
        }
        .frame(height: state.notchSize.height)
    }
}

private struct EarStat: View {
    let symbol: String
    /// Load used for the colour (0 good … 1 bad).
    let value: Double
    /// Number displayed; defaults to `value`.
    var shown: Double?
    var help: String?

    var body: some View {
        HStack(spacing: 3) {
            if symbol == "flame" {
                Image(systemName: "flame.fill").font(.system(size: 9)).foregroundStyle(RingGauge.color(for: value))
            } else {
                Circle().fill(RingGauge.color(for: value)).frame(width: 5, height: 5)
            }
            Text("\(Int(((shown ?? value) * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white.opacity(0.9))
        .help(help ?? (symbol == "cpu" ? "CPU %" : "Memory %"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(help ?? (symbol == "cpu" ? "CPU percent" : "Memory percent"))
    }
}
