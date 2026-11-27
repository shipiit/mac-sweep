import MacSweepCore
import SwiftUI

/// Live per-app network connections, sampled every few seconds only while this screen is visible.
struct NetworkMonitorView: View {
    @State private var model = NetworkMonitorModel()
    @State private var expanded: Set<Int32> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let online = model.count(for: .internet), flagged = model.count(for: .flagged)
                SummaryHero(
                    symbol: "point.3.connected.trianglepath.dotted", eyebrow: "On the network right now",
                    value: "\(online) app\(online == 1 ? "" : "s") online",
                    caption: "\(Format.count(model.activity.count)) apps have open sockets · " + (flagged == 0 ? "nothing untrusted is talking to the internet" : "\(flagged) untrusted program\(flagged == 1 ? " is" : "s are") online"),
                    tint: flagged == 0 ? nil : .orange,
                    segments: [
                        BarSegment(label: "Internet connections", value: Double(model.outboundTotal), color: .blue, detail: Format.count(model.outboundTotal)),
                        BarSegment(label: "Open ports", value: Double(model.listeningTotal), color: .teal, detail: Format.count(model.listeningTotal)),
                        BarSegment(label: "Flagged apps", value: Double(flagged), color: .orange, detail: Format.count(flagged)),
                    ]
                ) {
                    TextField("Search apps or hosts", text: $model.search).textFieldStyle(.roundedBorder).frame(width: 240)
                }
                if model.sample?.hasTraffic == false {
                    Text("Traffic counters are unavailable right now; connections are still shown.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                list
                Text("Shows your account's connections. Byte counts are totals since each app started.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Network Monitor")
        .sectionTabs(NetworkMonitorModel.Filter.allCases, selection: $model.filter, title: \.rawValue)
        .task { await model.monitor() }
    }

    @ViewBuilder private var list: some View {
        let apps = model.visible
        if model.sample == nil {
            Card { ProgressView("Sampling connections…").frame(maxWidth: .infinity) }
        } else if apps.isEmpty {
            Card {
                Label(emptyMessage, systemImage: model.filter == .flagged ? "checkmark.shield" : "network.slash")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 0) {
                ForEach(apps) { app in
                    NetworkAppRow(app: app, model: model, isExpanded: expansion(for: app.pid))
                    if app.id != apps.last?.id { Divider().padding(.leading, 60) }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        }
    }

    private var emptyMessage: String {
        if !model.search.trimmingCharacters(in: .whitespaces).isEmpty { return "No apps match your search." }
        switch model.filter {
        case .all: return "No network connections right now."
        case .internet: return "No app is connected to the internet right now."
        case .flagged: return "No untrusted code is connecting out."
        }
    }

    private func expansion(for pid: Int32) -> Binding<Bool> {
        Binding(get: { expanded.contains(pid) },
                set: { isOn in if isOn { expanded.insert(pid) } else { expanded.remove(pid) } })
    }
}
