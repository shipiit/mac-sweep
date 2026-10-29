import MacSweepCore
import SwiftUI

/// A profile's total, its clean action and an expandable per-category breakdown.
struct BrowserProfileRow: View {
    let profile: BrowserProfile
    let isCleaning: Bool
    let isBlocked: Bool
    let onClean: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right").frame(width: 12).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName).fontWeight(.medium)
                            Text(profile.directory).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(profile.displayName), \(Format.bytes(profile.totalSize))")
                .accessibilityHint(isExpanded ? "Hide breakdown" : "Show breakdown")
                Spacer()
                Text(Format.bytes(profile.totalSize)).font(.system(.callout, design: .monospaced))
                if isCleaning {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Clean Caches", systemImage: "trash", action: onClean)
                        .controlSize(.small)
                        .disabled(isBlocked || profile.size(of: .safe) == 0)
                        .help(isBlocked ? "Quit \(profile.browser.name) first." : "Moves \(Format.bytes(profile.size(of: .safe))) of caches to the Trash.")
                }
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(profile.components) { component in
                        ComponentLine(component: component)
                    }
                    Button("Reveal Profile Folder") { FileActions.reveal(profile.path) }.controlSize(.small)
                }
                .padding(.leading, 20)
            }
        }
    }
}

private struct ComponentLine: View {
    let component: ProfileComponent
    @State private var showSites = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 16).accessibilityHidden(true)
                Text(component.kind.rawValue)
                Pill(text: component.safety.rawValue, color: tint)
                if !component.sites.isEmpty {
                    Button(showSites ? "Hide sites" : "\(component.sites.count) sites") { showSites.toggle() }
                        .buttonStyle(.link).font(.caption)
                }
                Spacer()
                Text(Format.bytes(component.size)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            .help(component.kind.consequence)
            .accessibilityElement(children: .combine)
            if showSites {
                ForEach(component.sites.prefix(30)) { site in
                    HStack {
                        Text(site.origin ?? "Unknown site").font(.caption).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Format.bytes(site.size)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                }
                if component.sites.count > 30 {
                    Text("and \(component.sites.count - 30) more").font(.caption).foregroundStyle(.secondary).padding(.leading, 24)
                }
            }
        }
    }

    private var symbol: String {
        switch component.safety {
        case .safe: "checkmark.circle"
        case .review: "exclamationmark.triangle"
        case .keep: "lock"
        }
    }

    private var tint: Color {
        switch component.safety {
        case .safe: .green
        case .review: .orange
        case .keep: .secondary
        }
    }
}
