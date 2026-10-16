import MacSweepCore
import SwiftUI

struct NetworkSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let system = app.system
        let details = system.details
        InfoRow(label: "Connection", value: system.network?.isWiFi == true ? "Wi-Fi" : details.interface ?? "Offline", copyable: false)
        InfoRow(label: "Network name", value: system.network?.wifiName ?? "Hidden by macOS (Location permission)", copyable: system.network?.wifiName != nil)
        InfoRow(label: "Local IP", value: system.network?.ipv4 ?? "—", monospaced: true)
        ForEach(details.ipv6.prefix(2), id: \.self) { InfoRow(label: "IPv6", value: $0, monospaced: true) }
        InfoRow(label: "Router", value: details.gateway ?? "—", monospaced: true)
        InfoRow(label: "DNS", value: details.dnsServers.prefix(3).joined(separator: ", ").isEmpty ? "—" : details.dnsServers.prefix(3).joined(separator: ", "),
                monospaced: true)
        InfoRow(label: "MAC address", value: details.macAddress ?? "—", monospaced: true)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Public IP").foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            switch system.publicIP {
            case .hidden:
                Button("Show") { system.revealPublicIP() }
                    .controlSize(.small)
                    .help("Asks api.ipify.org for your public address. Nothing else is sent.")
            case .loading:
                ProgressView().controlSize(.small)
            case .shown(let ip):
                Text(ip).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Button { FileActions.copy(ip) } label: { Image(systemName: "doc.on.doc").font(.caption) }
                    .buttonStyle(.borderless).accessibilityLabel("Copy public IP")
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red)
                Button("Retry") { system.revealPublicIP() }.controlSize(.small)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.vertical, 3)
        InfoRow(label: "Listening ports", value: "\(app.ports.ports.count) (\(app.ports.ports.filter { !$0.isLocalOnly }.count) reachable from network)",
                copyable: false)
    }
}

/// Plain-text report for "Copy All". Leaves out the serial number and public IP on purpose.
@MainActor
enum SystemReport {
    static func text(app: AppModel) -> String {
        let mac = app.system.mac
        var lines = [
            "MacSweep system report — \(Date().formatted(date: .abbreviated, time: .shortened))",
            "",
            "Model: \(mac.modelName) (\(mac.modelIdentifier))",
            "Chip: \(mac.chip), \(ProcessInfo.processInfo.processorCount) cores",
            "Memory: \(Format.memory(mac.memory))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Uptime: \(app.system.uptime)",
        ]
        if let volume = app.monitor.volume {
            lines.append("Storage: \(Format.bytes(volume.used)) used of \(Format.bytes(volume.total)), \(Format.bytes(volume.available)) free")
        }
        if let memory = app.processes.memory {
            lines.append("Memory use: \(Format.memory(memory.used)), swap \(Format.memory(memory.swapUsed)), pressure \(memory.pressure.rawValue)")
        }
        if let battery = app.system.battery {
            lines.append("Battery: \(battery.percent)%, health \(battery.health.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"), \(battery.cycleCount ?? 0) cycles")
        }
        lines.append("Local IP: \(app.system.network?.ipv4 ?? "—"), router \(app.system.details.gateway ?? "—")")
        lines.append("DNS: \(app.system.details.dnsServers.joined(separator: ", "))")
        for check in app.security.protections {
            lines.append("\(check.title): \(check.state == .on ? "On" : check.state == .off ? "Off" : "Unknown")")
        }
        for screen in NSScreen.screens {
            lines.append("Display: \(screen.localizedName) \(Int(screen.frame.width))×\(Int(screen.frame.height))")
        }
        return lines.joined(separator: "\n")
    }
}
