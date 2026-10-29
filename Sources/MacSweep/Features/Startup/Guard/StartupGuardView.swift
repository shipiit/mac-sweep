import MacSweepCore
import SwiftUI

/// Startup Items tab: the Startup Guard switch, items it is holding, and what it has done.
struct StartupGuardView: View {
    let startupGuard: StartupGuard
    @State private var pendingRemoval: HeldStartupItem?
    @Environment(\.appAccent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                toggleCard
                if let message = startupGuard.message {
                    NoticeBanner(symbol: "exclamationmark.triangle", title: "Couldn't finish", message: message,
                                 actionTitle: "Dismiss") { startupGuard.message = nil }
                }
                heldCard
                StartupGuardHistory(events: startupGuard.history)
            }
            .padding(20)
        }
        .confirmationDialog(removalTitle, isPresented: isConfirmingRemoval, presenting: pendingRemoval) { entry in
            Button("Move to Trash", role: .destructive) { Task { await startupGuard.remove(entry) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The item is unloaded and its plist (and program, when it's safe to) is moved to the Trash, where you can restore it.")
        }
    }

    private var toggleCard: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(symbol: startupGuard.isEnabled ? "shield.lefthalf.filled" : "shield.slash",
                          tint: startupGuard.isEnabled ? accent : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Startup Guard").font(.headline)
                        Pill(text: startupGuard.isEnabled ? "On" : "Off", color: startupGuard.isEnabled ? accent : .secondary)
                        if startupGuard.isChecking { ProgressView().controlSize(.mini) }
                    }
                    Text("""
                    When on, everything set to start automatically right now is approved. Any launch agent added later in your \
                    Library is stopped and disabled at once; new items for all users or system daemons are reported so you can \
                    block them with your password. Off by default because installers you trust also add these.
                    """)
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("Startup Guard", isOn: enabledBinding).toggleStyle(.switch).labelsHidden()
                    .accessibilityLabel("Startup Guard")
            }
        }
    }

    private var heldCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Held items", subtitle: "New startup items waiting for your decision")
                    Spacer()
                    if startupGuard.isEnabled {
                        Button("Check Now", systemImage: "arrow.clockwise") { Task { await startupGuard.check() } }
                            .disabled(startupGuard.isChecking)
                    }
                }
                if startupGuard.held.isEmpty {
                    Text(startupGuard.isEnabled ? "Nothing new has tried to start automatically." : "Turn the guard on to hold new startup items.")
                        .foregroundStyle(.secondary)
                }
                ForEach(startupGuard.held) { entry in
                    HeldStartupItemRow(entry: entry, isBusy: startupGuard.busy.contains(entry.id),
                                       onApprove: { Task { await startupGuard.approve(entry) } },
                                       onBlock: { Task { await startupGuard.block(entry) } },
                                       onKeepBlocked: { startupGuard.keepBlocked(entry) },
                                       onRemove: { pendingRemoval = entry })
                }
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { startupGuard.isEnabled }, set: { value in Task { await startupGuard.setEnabled(value) } })
    }

    private var removalTitle: String {
        pendingRemoval.map { "Move \($0.fingerprint.name) to the Trash?" } ?? ""
    }

    private var isConfirmingRemoval: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }
}
