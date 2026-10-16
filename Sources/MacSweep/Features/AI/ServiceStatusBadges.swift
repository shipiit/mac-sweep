import MacSweepCore
import SwiftUI

/// One compact status badge per tool, following the page's tool filter. Each expands to list incidents and services.
struct ServiceStatusBadges: View {
    let model: AIUsageModel
    let providers: [AIProvider]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(providers) { provider in
                ServiceStatusBadge(provider: provider, status: model.serviceStatus[provider],
                                   isUnavailable: model.unavailableStatus.contains(provider))
            }
        }
        .task {
            while !Task.isCancelled {
                await model.refreshServiceStatus()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }
}

private struct ServiceStatusBadge: View {
    let provider: AIProvider
    let status: ServiceStatus?
    let isUnavailable: Bool
    @State private var isExpanded = false

    var body: some View {
        let level = status?.level ?? .unknown
        let links = ServiceStatus.Links.of(provider)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { isExpanded.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: ServiceLevelStyle.symbol(level)).foregroundStyle(ServiceLevelStyle.color(level))
                        Text(provider.rawValue).font(.callout.weight(.semibold))
                        Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        if let count = status?.incidents.count, count > 0 {
                            Text("\(count) incident\(count == 1 ? "" : "s")").font(.caption.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(ServiceLevelStyle.color(level).opacity(0.15), in: Capsule())
                        }
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(provider.rawValue) status: \(summary). \(isExpanded ? "Collapse" : "Expand") details")
                Spacer(minLength: 6)
                Button("Status", systemImage: "arrow.up.right") { FileActions.open(url: links.statusPage) }
                Button("Dashboard", systemImage: "arrow.up.right") { FileActions.open(url: links.dashboard) }
            }
            if isExpanded { details }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ServiceLevelStyle.color(level).opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var summary: String {
        status?.description ?? (isUnavailable ? "Status unavailable" : "Checking…")
    }

    @ViewBuilder private var details: some View {
        Divider()
        if let incidents = status?.incidents, !incidents.isEmpty {
            ForEach(incidents) { incident in
                HStack(spacing: 6) {
                    Image(systemName: ServiceLevelStyle.symbol(incident.impact)).foregroundStyle(ServiceLevelStyle.color(incident.impact))
                    Text(incident.name).font(.caption.weight(.medium)).lineLimit(2)
                    Spacer(minLength: 4)
                    if !incident.state.isEmpty { Text(incident.state).font(.caption).foregroundStyle(.secondary) }
                    if let link = incident.link {
                        Button { FileActions.open(url: link) } label: { Image(systemName: "arrow.up.right.square") }
                            .buttonStyle(.borderless).help("Open incident").accessibilityLabel("Open incident \(incident.name)")
                    }
                }
            }
        } else {
            Label("No open incidents", systemImage: "checkmark.seal").font(.caption).foregroundStyle(.secondary)
        }
        if let components = status?.components, !components.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(components) { component in
                    HStack(spacing: 5) {
                        Image(systemName: ServiceLevelStyle.symbol(component.level)).foregroundStyle(ServiceLevelStyle.color(component.level))
                        Text(component.name).lineLimit(1)
                    }
                    .font(.caption)
                    .help(component.detail)
                    .accessibilityLabel("\(component.name): \(component.detail)")
                }
            }
        }
    }
}

enum ServiceLevelStyle {
    static func symbol(_ level: ServiceStatus.Level) -> String {
        switch level {
        case .operational: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .outage: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    static func color(_ level: ServiceStatus.Level) -> Color {
        switch level {
        case .operational: return .green
        case .degraded: return .orange
        case .outage: return .red
        case .unknown: return .secondary
        }
    }
}
