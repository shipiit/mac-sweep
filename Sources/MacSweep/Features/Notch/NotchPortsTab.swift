import MacSweepCore
import SwiftUI

/// Searchable listening ports: number, owning app, protocol, local/network badge, open and stop.
struct NotchPortsTab: View {
    @Environment(AppModel.self) private var app
    let onQuit: (Int32, String) -> Void
    @State private var search = ""

    var body: some View {
        let query = search.lowercased()
        let ports = app.ports.ports.filter { query.isEmpty || String($0.port).contains(query) || $0.command.lowercased().contains(query) }
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                TextField("Search ports or processes…", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if ports.isEmpty {
                Text(search.isEmpty ? "Nothing is listening right now." : "No matches.").foregroundStyle(.white.opacity(0.6)).padding(.top, 20)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 6) {
                    ForEach(ports.prefix(40)) { port in row(port) }
                }
            }
        }
    }

    private func row(_ port: ListeningPort) -> some View {
        HStack(spacing: 8) {
            Text(":\(port.port)").font(.system(size: 13, weight: .bold, design: .monospaced)).frame(width: 58, alignment: .leading)
            ProcessIcon(pid: port.pid, path: nil, size: 18)
            Text(port.command).lineLimit(1)
            Spacer(minLength: 2)
            Text(port.proto).font(.system(size: 9, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 2)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            Image(systemName: port.isLocalOnly ? "lock.fill" : "globe")
                .foregroundStyle(port.isLocalOnly ? .green : .orange)
                .help(port.isLocalOnly ? "Only reachable from this Mac" : "Reachable from the network")
                .accessibilityLabel(port.isLocalOnly ? "Local only" : "Reachable from the network")
            if port.proto == "TCP" {
                Button { FileActions.open(url: URL(string: "http://localhost:\(port.port)")) } label: { Image(systemName: "safari") }
                    .buttonStyle(.plain).help("Open http://localhost:\(port.port)").accessibilityLabel("Open port \(port.port)")
            }
            InlineConfirmButton(help: "Stop \(port.command)") { onQuit(port.pid, port.command) }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
