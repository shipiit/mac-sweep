import MacSweepCore
import SwiftUI

/// Smart Scan's result: one ranked list of everything found, with the fixes ticked and one button to run them.
struct SmartFindingsCard: View {
    let findings: [SmartFinding]
    @Binding var steps: Set<OptimizeStep>
    let onFix: () -> Void
    let onScanAgain: () -> Void
    @Environment(AppModel.self) private var app
    @State private var confirming = false

    var body: some View {
        let urgent = findings.filter { $0.level == .urgent }.count
        let reclaim = SmartFindings.bytes(findings, steps: steps)
        VStack(alignment: .leading, spacing: 14) {
            SummaryHero(
                symbol: findings.isEmpty ? "checkmark.seal.fill" : "sparkles",
                eyebrow: findings.isEmpty ? "Scan complete" : "Ready to fix",
                value: findings.isEmpty ? "All clear" : reclaim > 0 ? Format.bytes(reclaim) : "\(steps.count) fix\(steps.count == 1 ? "" : "es")",
                caption: findings.isEmpty ? "Nothing to clean, fix or update."
                    : [urgent > 0 ? "\(urgent) security issue\(urgent == 1 ? "" : "s")" : nil,
                       "\(findings.filter { $0.level == .safe }.count) safe clean-ups",
                       "\(findings.filter { $0.level == .review }.count) to review"].compactMap { $0 }.joined(separator: " · "),
                tint: urgent > 0 ? .red : .green,
                segments: findings.filter { $0.bytes > 0 }.prefix(6).enumerated().map { index, finding in
                    BarSegment(label: finding.title, value: Double(finding.bytes), color: Self.palette[index % Self.palette.count], detail: Format.bytes(finding.bytes))
                }
            ) {
                Button { confirming = true } label: { Label("Fix Selected", systemImage: "wand.and.stars").frame(minWidth: 130) }
                    .buttonStyle(.borderedProminent).disabled(steps.isEmpty).keyboardShortcut(.defaultAction)
                Button(action: onScanAgain) { Label("Scan Again", systemImage: "arrow.clockwise").frame(minWidth: 130) }
            }
            if !findings.isEmpty {
                Card(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(findings) { finding in
                            FindingRow(finding: finding, isOn: binding(finding.step)) { open(finding) }
                            if finding.id != findings.last?.id { Divider().padding(.leading, 74) }
                        }
                        Divider()
                        ForEach([OptimizeStep.maintenance, .flushDNSAndRAM]) { step in
                            Toggle(isOn: binding(step)) {
                                Text(step == .maintenance ? "Also rebuild the app and font caches" : "Also flush the DNS cache and free up RAM (asks for your password)").font(.callout)
                            }
                            .toggleStyle(.checkbox).padding(.horizontal, 14).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 1100)
        .alert("Fix \(steps.count) selected?", isPresented: $confirming) {
            Button("Fix", action: onFix)
            Button("Cancel", role: .cancel) {}
        } message: { Text(confirmation) }
    }

    private static let palette: [Color] = [.green, .teal, .blue, .purple, .orange, .pink]

    private func binding(_ step: OptimizeStep?) -> Binding<Bool> {
        Binding(get: { step.map(steps.contains) ?? false }, set: { isOn in
            guard let step else { return }
            if isOn { steps.insert(step) } else { steps.remove(step) }
        })
    }

    private func open(_ finding: SmartFinding) {
        if let section = SidebarSection(rawValue: finding.page) { app.section = section }
    }

    private var confirmation: String {
        var lines = OptimizePlan.steps(enabled: steps).map { step -> String in
            let bytes = SmartFindings.bytes(findings, steps: [step])
            let size = bytes > 0 ? " (\(Format.bytes(bytes)))" : ""
            return "• \(step.title)\(size)\(step.isPermanent ? ": deleted for good" : step.requiresAdmin ? ": asks for your password" : "")"
        }
        lines.append(steps.contains(.trashBins) ? "\nEmptying the Trash can't be undone." : "\nEverything else goes to the Trash, so you can put it back.")
        return lines.joined(separator: "\n")
    }
}

private struct FindingRow: View {
    let finding: SmartFinding
    @Binding var isOn: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Fix \(finding.title)", isOn: $isOn).labelsHidden().toggleStyle(.checkbox)
                .opacity(finding.step == nil ? 0 : 1).disabled(finding.step == nil).accessibilityHidden(finding.step == nil)
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(finding.title).font(.callout.weight(.semibold))
                    Pill(text: label, color: color)
                }
                Text(finding.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if finding.bytes > 0 { FigureText(value: Format.bytes(finding.bytes), size: 18) }
            Button(finding.step == nil ? "Review" : "Details", action: open).frame(minWidth: 76, alignment: .trailing)
                .help("Open \(finding.page)")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var label: String {
        switch finding.level {
        case .urgent: "Security"
        case .safe: "Safe"
        case .review: "Your call"
        }
    }

    private var symbol: String {
        switch finding.level {
        case .urgent: "exclamationmark.shield.fill"
        case .safe: "checkmark"
        case .review: "eye"
        }
    }

    private var color: Color {
        switch finding.level {
        case .urgent: .red
        case .safe: .green
        case .review: .orange
        }
    }
}
