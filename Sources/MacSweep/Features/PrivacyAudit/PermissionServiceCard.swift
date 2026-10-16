import MacSweepCore
import SwiftUI

/// One privacy service with every app that asked for it; collapsible so long lists stay scannable.
struct PermissionServiceCard: View {
    let group: TCCServiceGroup
    let model: PrivacyPermissionsModel
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider()
                ForEach(group.entries) { entry in
                    PermissionEntryRow(entry: entry, info: model.info(for: entry.client), flag: model.flags[entry.id])
                    if entry.id != group.entries.last?.id { Divider().padding(.leading, 60) }
                }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    SymbolBadge(symbol: group.service.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(group.service.title).font(.headline)
                            if group.service.isPowerful { Pill(text: "Powerful", color: .orange) }
                        }
                        Text("\(group.allowedCount) allowed · \(group.entries.count - group.allowedCount) denied")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.service.title), \(group.allowedCount) allowed")
            .accessibilityHint(isExpanded ? "Collapse" : "Expand")
            Button("Open in System Settings") { FileActions.open(url: group.service.settingsURL) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct PermissionEntryRow: View {
    let entry: TCCEntry
    let info: TCCClientInfo
    let flag: TCCRiskFlag?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(info.name).fontWeight(.medium).lineLimit(1)
                    if entry.database == .system { Pill(text: "System-wide") }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let flag {
                    Label(flag.reason, systemImage: flag.severity.symbol)
                        .font(.callout)
                        .foregroundStyle(flag.severity.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let flag { SeverityPill(severity: flag.severity) }
            authorizationPill
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        if let path = info.path {
            FileIcon(path: path, size: 32)
        } else {
            Image(systemName: "questionmark.app.dashed")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        }
    }

    private var subtitle: String {
        var parts = [entry.client.raw]
        if let target = entry.target { parts.append("controls \(target)") }
        parts.append(info.signature?.title ?? "Not found on this Mac")
        return parts.joined(separator: " · ")
    }

    private var authorizationPill: some View {
        let isGranted = entry.authorization.isGranted
        return Label(entry.authorization.title, systemImage: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(isGranted ? Color.green : Color.secondary)
            .background((isGranted ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
            .fixedSize()
    }
}
