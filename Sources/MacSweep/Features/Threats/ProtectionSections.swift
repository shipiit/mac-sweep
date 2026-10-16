import MacSweepCore
import SwiftUI

struct DownloadProtectionSection: View {
    @Bindable var threats: ThreatCenter
    @Environment(\.appAccent) private var accent

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: threats.isProtectionOn ? "checkmark.shield.fill" : "shield.slash").font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white).frame(width: 60, height: 60)
                .background(threats.isProtectionOn ? accent : .secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(threats.isProtectionOn ? "Download Protection is on" : "Download Protection is off").font(.title3.weight(.semibold))
                Text("Every new file in Downloads is checked as soon as it finishes. Clear threats are moved to quarantine before you can open them; anything suspicious gets a notification.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("Download Protection", isOn: $threats.isProtectionOn).toggleStyle(.switch).labelsHidden().controlSize(.large)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent activity").font(.headline)
                if threats.events.isEmpty {
                    Label("Nothing suspicious downloaded since MacSweep started.", systemImage: "checkmark.seal").foregroundStyle(.secondary)
                }
                ForEach(threats.events) { event in
                    HStack(spacing: 10) {
                        Image(systemName: event.verdict.isAutoQuarantine ? "lock.shield.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(event.verdict.isAutoQuarantine ? .red : .orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(event.action): \(event.verdict.facts.name)").fontWeight(.medium)
                            Text(event.verdict.reasons.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.relative(event.date)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct QuarantineSection: View {
    let threats: ThreatCenter
    @State private var discarding: QuarantinedItem?

    var body: some View {
        if threats.quarantined.isEmpty {
            Label("Quarantine is empty.", systemImage: "lock.shield").foregroundStyle(.secondary).padding(.vertical, 20)
        }
        ForEach(threats.quarantined) { item in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.doc.fill").font(.title2).foregroundStyle(.secondary).frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).fontWeight(.semibold)
                    Text(item.reasons.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                    Text("Was at \(Format.path(item.originalPath)) · quarantined \(Format.relative(item.date))" + (item.origin.map { " · from \($0)" } ?? ""))
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Restore") { threats.restore(item) }
                Button("Delete…") { discarding = item }.tint(.red)
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        }
        .alert("Move \(discarding?.name ?? "") to the Trash?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }),
               presenting: discarding) { item in
            Button("Move to Trash", role: .destructive) { threats.discard(item) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("You can still recover it from the Trash until you empty it.") }
    }
}
