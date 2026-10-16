import MacSweepCore
import SwiftUI

/// After the scan: choose what to clean, then one big Run button.
struct OptimizeReviewCard: View {
    @Binding var enabled: Set<OptimizeStep>
    let junkSize: UInt64
    let trashSize: UInt64
    let onRun: () -> Void
    @Environment(\.appAccent) private var accent
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Clean up now").font(.title2.weight(.semibold))
                ForEach(OptimizeStep.allCases) { step in
                    Toggle(isOn: Binding(get: { enabled.contains(step) }, set: { isOn in
                        if isOn { enabled.insert(step) } else { enabled.remove(step) }
                    })) {
                        HStack(spacing: 10) {
                            OptimizeStepIcon(step: step)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.title).fontWeight(.medium)
                                Text(detail(step)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let size = size(step) { Text(Format.bytes(size)).monospacedDigit().foregroundStyle(.secondary) }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Button { confirming = true } label: {
                Text("Run").font(.title2.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 110, height: 110)
                    .background(accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(enabled.isEmpty)
            .opacity(enabled.isEmpty ? 0.4 : 1)
            .accessibilityLabel("Run clean-up")
        }
        .padding(22)
        .frame(maxWidth: 820)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .alert("Run clean-up?", isPresented: $confirming) {
            Button("Run", action: onRun)
            Button("Cancel", role: .cancel) {}
        } message: { Text(confirmation) }
    }

    private func size(_ step: OptimizeStep) -> UInt64? {
        switch step {
        case .systemJunk: junkSize
        case .trashBins: trashSize
        default: nil
        }
    }

    private func detail(_ step: OptimizeStep) -> String {
        switch step {
        case .systemJunk: "Only items marked safe; anything in use is skipped. Goes to the Trash."
        case .trashBins: "Permanently deletes what's in your Trash."
        case .maintenance: "Rebuild Launch Services, clear font caches."
        case .flushDNSAndRAM: "Needs your password once."
        }
    }

    private var confirmation: String {
        var lines: [String] = []
        if enabled.contains(.systemJunk) { lines.append("Moves \(Format.bytes(junkSize)) of safe junk to the Trash.") }
        if enabled.contains(.trashBins) { lines.append("Permanently empties the Trash (\(Format.bytes(trashSize))\(enabled.contains(.systemJunk) ? " plus the junk above" : "")). This can't be undone.") }
        if enabled.contains(.maintenance) { lines.append("Runs maintenance scripts.") }
        if enabled.contains(.flushDNSAndRAM) { lines.append("Asks for your password to flush DNS and free up RAM.") }
        return lines.joined(separator: "\n")
    }
}

/// "Optimizing your Mac…": per-step status, a progress ring Stop button, then the result.
struct OptimizeRunView: View {
    let runner: OptimizeRunner
    let onDone: () -> Void
    @Environment(\.appAccent) private var accent

    var body: some View {
        VStack(spacing: 24) {
            Text(runner.isRunning ? (runner.isStopping ? "Stopping after this step…" : "Optimizing your Mac…") : "Clean-up complete")
                .font(.largeTitle.weight(.semibold))
            if !runner.isRunning {
                Text("\(Format.bytes(runner.freed)) freed").font(.title2.weight(.medium)).foregroundStyle(accent)
            }
            VStack(spacing: 0) {
                ForEach(runner.steps) { step in
                    row(step)
                    if step != runner.steps.last { Divider().padding(.leading, 56) }
                }
            }
            .frame(maxWidth: 620)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5)))
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 6)
                Circle().trim(from: 0, to: runner.progress).stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Button(runner.isRunning ? "Stop" : "Done") { runner.isRunning ? runner.stop() : onDone() }
                    .buttonStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .frame(width: 96, height: 96)
                    .background(.quaternary.opacity(0.6), in: Circle())
                    .disabled(runner.isStopping)
            }
            .frame(width: 112, height: 112)
            .accessibilityLabel(runner.isRunning ? "Stop clean-up, \(Int(runner.progress * 100)) percent done" : "Done")
        }
    }

    private func row(_ step: OptimizeStep) -> some View {
        let state = runner.states[step] ?? .pending
        return HStack(spacing: 14) {
            OptimizeStepIcon(step: step)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).fontWeight(.medium)
                if let note = note(state) { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            status(state)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func note(_ state: OptimizeStepState) -> String? {
        switch state {
        case .done(_, let note): note
        case .warning(let text), .skipped(let text): text
        case .running: "Running…"
        case .pending: nil
        }
    }

    @ViewBuilder private func status(_ state: OptimizeStepState) -> some View {
        switch state {
        case .pending: Image(systemName: "ellipsis").foregroundStyle(.tertiary).accessibilityLabel("Waiting")
        case .running: ProgressView().controlSize(.small)
        case .done(let freed, _):
            HStack(spacing: 6) {
                if freed > 0 { Text(Format.bytes(freed)).monospacedDigit().foregroundStyle(.secondary) }
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Done")
            }
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel("Warning")
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary).accessibilityLabel("Skipped")
        }
    }
}

struct OptimizeStepIcon: View {
    let step: OptimizeStep

    var body: some View {
        let (symbol, color): (String, Color) = switch step {
        case .systemJunk: ("trash.circle.fill", .pink)
        case .trashBins: ("trash.fill", .green)
        case .maintenance: ("wrench.and.screwdriver.fill", .blue)
        case .flushDNSAndRAM: ("memorychip.fill", .orange)
        }
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}
