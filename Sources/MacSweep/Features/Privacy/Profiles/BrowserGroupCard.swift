import MacSweepCore
import SwiftUI

/// One browser: its profiles plus browser-wide on-device models.
struct BrowserGroupCard: View {
    let group: BrowserProfileGroup
    let cleaning: String?
    let blockedReason: String?
    let onClean: (BrowserProfile) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconBadge(symbol: "globe", tint: .secondary, size: 30)
                    Text(group.browser.name).font(.headline)
                    Text(Format.bytes(group.totalSize)).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    if blockedReason != nil { Pill(text: "Running · quit to clean", color: .orange) }
                }
                ForEach(group.profiles) { profile in
                    Divider()
                    BrowserProfileRow(profile: profile, isCleaning: cleaning == profile.id, isBlocked: blockedReason != nil) {
                        onClean(profile)
                    }
                }
                if let models = group.modelsPath {
                    Divider()
                    HStack {
                        Label("On-device AI models", systemImage: "cpu").font(.callout)
                        Pill(text: ProfileDataSafety.keep.rawValue)
                        Spacer()
                        Text(Format.bytes(group.modelsSize)).font(.system(.callout, design: .monospaced))
                        Button("Reveal") { FileActions.reveal(models) }.controlSize(.small)
                    }
                    .help("Shared by all profiles. The browser downloads these again if they're removed.")
                }
            }
        }
    }
}
