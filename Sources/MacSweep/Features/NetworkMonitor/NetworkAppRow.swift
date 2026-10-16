import MacSweepCore
import SwiftUI

struct NetworkAppRow: View {
    let app: AppNetworkActivity
    let model: NetworkMonitorModel
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { isExpanded.toggle() } label: { summary }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded ? "Hide connections" : "Show connections")
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(app.connections) { ConnectionLine(connection: $0, model: model) }
                }
                .padding(.leading, 60)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
        }
        .background(app.flag.map { $0.severity.color.opacity(0.06) } ?? Color.clear)
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .foregroundStyle(.secondary)
                .frame(width: 10, height: 28)
                .accessibilityHidden(true)
            ProcessIcon(pid: app.pid, path: app.path, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(app.name).fontWeight(.medium).lineLimit(1)
                    if let signature = app.signature, !signature.isTrusted { Pill(text: signature.title) }
                }
                counts
                let hosts = model.topHosts(app)
                if !hosts.isEmpty {
                    Text(hosts.joined(separator: ", "))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                if let flag = app.flag {
                    Label(flag.reason, systemImage: flag.severity.symbol)
                        .font(.callout).foregroundStyle(flag.severity.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let traffic = app.traffic {
                VStack(alignment: .trailing, spacing: 2) {
                    Label(Format.bytes(traffic.bytesIn), systemImage: "arrow.down")
                    Label(Format.bytes(traffic.bytesOut), systemImage: "arrow.up")
                }
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Received \(Format.bytes(traffic.bytesIn)), sent \(Format.bytes(traffic.bytesOut))")
            }
            if let flag = app.flag { SeverityPill(severity: flag.severity) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var counts: some View {
        HStack(spacing: 10) {
            Label("\(app.establishedCount) established", systemImage: "arrow.left.arrow.right")
            Label("\(app.outboundCount) internet", systemImage: "globe")
            if app.listeningCount > 0 { Label("\(app.listeningCount) listening", systemImage: "ear") }
        }
        .font(.caption).foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }
}

private struct ConnectionLine: View {
    let connection: NetConnection
    let model: NetworkMonitorModel

    var body: some View {
        HStack(spacing: 8) {
            Text(connection.proto.uppercased()).frame(width: 40, alignment: .leading).foregroundStyle(.secondary)
            Text(connection.local?.display ?? "*").frame(width: 190, alignment: .leading).lineLimit(1).truncationMode(.middle)
            Image(systemName: connection.kind == .listening ? "ear" : "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(connection.remote.map(model.displayHost) ?? "—").lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(connection.state ?? "—").foregroundStyle(.secondary)
            if connection.isOutboundInternet { Pill(text: "Internet") }
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }
}
