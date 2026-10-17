import MacSweepCore
import SwiftUI

/// Numbered explainer step used on the protection tabs.
struct HowItWorksStep: View {
    let number: Int
    let symbol: String
    let title: String
    let detail: String
    @Environment(\.appAccent) private var accent

    var body: some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconBadge(symbol: symbol, tint: accent, size: 34)
                    Spacer()
                    Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).background(.quaternary.opacity(0.5), in: Circle())
                }
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DownloadProtectionSection: View {
    @Bindable var threats: ThreatCenter
    @Environment(\.appAccent) private var accent

    var body: some View {
        let log = threats.downloadsLog
        VStack(alignment: .leading, spacing: 16) {
            Panel(padding: 22) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 18) {
                        Image(systemName: threats.isProtectionOn ? "checkmark.shield.fill" : "shield.slash")
                            .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 66, height: 66)
                            .background(threats.isProtectionOn ? accent : .secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(threats.isProtectionOn ? "Download Protection is on" : "Download Protection is off").font(.system(size: 26, weight: .bold))
                            Text("Every new file in your Downloads folder is checked the moment it finishes downloading. Clear threats are moved to quarantine before you can open them; anything suspicious gets a notification.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("Download Protection", isOn: $threats.isProtectionOn).toggleStyle(.switch).labelsHidden().controlSize(.large)
                    }
                    HStack(spacing: 12) {
                        InfoTile(symbol: "arrow.down.doc", tint: .blue, title: "Downloads checked", value: "\(log.count) recent")
                        InfoTile(symbol: "lock.shield", tint: .red, title: "Blocked", value: "\(log.filter { $0.outcome == .quarantined }.count)",
                                 valueColor: log.contains { $0.outcome == .quarantined } ? .red : .primary)
                        InfoTile(symbol: "exclamationmark.triangle", tint: .orange, title: "Flagged for review", value: "\(log.filter { $0.outcome == .flagged }.count)")
                    }
                }
            }
            Text("How it works").font(.title3.weight(.semibold))
            HStack(alignment: .top, spacing: 12) {
                HowItWorksStep(number: 1, symbol: "eye", title: "Watches Downloads", detail: "macOS tells MacSweep the moment something lands in your Downloads folder. No constant scanning.")
                HowItWorksStep(number: 2, symbol: "hourglass", title: "Waits until it's finished", detail: "Partial files (.crdownload, .download, .part) are skipped until the download completes.")
                HowItWorksStep(number: 3, symbol: "checklist", title: "Checks what it is", detail: "File type, code signature, Gatekeeper's verdict, disguised names, known adware and hidden programs.")
                HowItWorksStep(number: 4, symbol: "lock.shield", title: "Blocks or warns", detail: "Clear threats go to quarantine and can't run. Suspicious files trigger a notification. Safe files are left alone.")
            }
            .fixedSize(horizontal: false, vertical: true)
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Recent downloads", systemImage: "clock.arrow.circlepath").font(.title3.weight(.semibold))
                        Spacer()
                        Text("Last \(DownloadLog.limit) files · saved across restarts").font(.caption).foregroundStyle(.secondary)
                    }
                    if log.isEmpty {
                        Label("Nothing downloaded since Download Protection started. New downloads will appear here with their result.",
                              systemImage: "tray").foregroundStyle(.secondary).padding(.vertical, 10)
                    }
                    ForEach(log) { record in DownloadRow(record: record) }
                }
            }
            Label("Only programs, installers, click-to-run scripts and files pretending to be documents can run code, so those get the full check. Documents, images and media are logged as safe file types.",
                  systemImage: "info.circle").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DownloadRow: View {
    let record: DownloadRecord
    @State private var isExpanded = false

    var body: some View {
        let (label, symbol, color) = style(record.outcome)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                FileIcon(path: record.path, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                    Text([record.kind, Format.bytes(record.size), record.originHost.map { "from \($0)" }, record.signer].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(Format.relative(record.date)).font(.caption).foregroundStyle(.secondary)
                Label(label, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(color.opacity(0.12), in: Capsule())
                if FileManager.default.fileExists(atPath: record.path) {
                    Button { FileActions.reveal(record.path) } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless).help("Reveal in Finder").accessibilityLabel("Reveal \(record.name)")
                }
                if !record.reasons.isEmpty {
                    Button { isExpanded.toggle() } label: { Image(systemName: isExpanded ? "chevron.up" : "chevron.down") }
                        .buttonStyle(.borderless).accessibilityLabel(isExpanded ? "Hide details" : "Show details")
                }
            }
            if isExpanded {
                ForEach(record.reasons, id: \.self) { Text("• \($0)").font(.callout).foregroundStyle(.secondary).padding(.leading, 42) }
            }
        }
        .padding(.vertical, 4)
    }

    private func style(_ outcome: DownloadRecord.Outcome) -> (String, String, Color) {
        switch outcome {
        case .safeType: ("Safe file type", "checkmark.circle.fill", .green)
        case .passed: ("Checked: clean", "checkmark.shield.fill", .green)
        case .flagged: ("Flagged", "exclamationmark.triangle.fill", .orange)
        case .quarantined: ("Quarantined", "lock.shield.fill", .red)
        }
    }
}
