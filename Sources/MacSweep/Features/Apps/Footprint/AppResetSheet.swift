import MacSweepCore
import SwiftUI

/// Confirmation for "Reset app": what reset means, then every path and its size.
struct AppResetSheet: View {
    let plan: AppFootprintPlan
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                FileIcon(path: plan.app.path, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset \(plan.app.name)?").font(.title3.weight(.semibold))
                    Text("\(plan.targets.count) items · \(Format.bytes(plan.total))")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Card(padding: 12) {
                Label {
                    Text("""
                    \(plan.app.name) will start as if freshly installed. Its settings, sign-ins, \
                    and any data kept only on this Mac are lost. The app itself stays installed. \
                    Everything below moves to the Trash, so you can restore it until you empty the Trash.
                    """)
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                .font(.callout)
            }
            List {
                Section("Moves to the Trash") {
                    ForEach(plan.targets) { target in row(target) }
                }
                if !plan.refused.isEmpty {
                    Section("Kept (protected)") {
                        ForEach(plan.refused, id: \.path) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Format.path(item.path)).lineLimit(1).truncationMode(.middle)
                                Text(item.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Reset \(plan.app.name)", role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(plan.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
    }

    private func row(_ target: CleanupTarget) -> some View {
        let category = plan.categories[target.path]
        return HStack(spacing: 8) {
            Image(systemName: category?.symbol ?? "folder").foregroundStyle(category?.color ?? .secondary).frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(Format.path(target.path)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Text(category?.title ?? "Data").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.bytes(target.size)).monospacedDigit().foregroundStyle(.secondary)
            Button { FileActions.reveal(target.path) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")
                .accessibilityLabel("Reveal \(Format.path(target.path)) in Finder")
        }
        .font(.callout)
    }
}
