import MacSweepCore
import SwiftUI

/// One held launch item with its state (icon + text) and the actions that fit that state.
struct HeldStartupItemRow: View {
    let entry: HeldStartupItem
    let isBusy: Bool
    let onApprove: () -> Void
    let onBlock: () -> Void
    let onKeepBlocked: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isBlocked ? "hand.raised.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isBlocked ? Color.secondary : Color.orange)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.fingerprint.name).fontWeight(.medium).lineLimit(1)
                    Pill(text: isBlocked ? "Blocked" : "Not blocked yet", color: isBlocked ? .secondary : .orange)
                    Pill(text: entry.fingerprint.kind.label)
                }
                Text(entry.fingerprint.executable.map(Format.path) ?? "No program")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text("Found \(Format.relative(entry.detected)) · \(Format.path(entry.plistPath))")
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                actions
            }
        }
        .controlSize(.small)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var actions: some View {
        Button("Approve", action: onApprove)
            .help(isBlocked ? "Re-enable it and let it start automatically." : "Let it start automatically.")
        if isBlocked {
            Button("Keep Blocked", action: onKeepBlocked).help("Leave it disabled and stop listing it here.")
        } else {
            Button(needsPassword ? "Block…" : "Block", action: onBlock)
                .help(needsPassword ? "Stops and disables it. Asks for your password." : "Stops and disables it.")
        }
        Button("Reveal") { FileActions.reveal(entry.plistPath) }
        Button("Remove…", role: .destructive, action: onRemove)
    }

    private var isBlocked: Bool { entry.status == .blocked }
    private var needsPassword: Bool { entry.fingerprint.kind == .daemon }
}
