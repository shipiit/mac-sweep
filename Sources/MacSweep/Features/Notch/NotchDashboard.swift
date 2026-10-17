import Darwin
import MacSweepCore
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case system = "System"
    case apps = "Apps"
    case ports = "Ports"
    case ai = "AI"
    case clean = "Clean"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .system: "gauge.with.dots.needle.50percent"
        case .apps: "square.stack.3d.up"
        case .ports: "network"
        case .ai: "flame"
        case .clean: "sparkles"
        }
    }
}

/// The hover panel, NotchNook-style: tab chips on top, one focused view per tab.
struct NotchDashboard: View {
    let topInset: CGFloat
    @Environment(AppModel.self) private var app
    @AppStorage("notchTab") private var tab: NotchTab = .system

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(NotchTab.allCases) { item in
                    Button { tab = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(tab == item ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(tab == item ? .white : .white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
                    .help("Settings")
                    .accessibilityLabel("Settings")
                Button { open(.overview) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
                    .help("Open MacSweep")
                    .accessibilityLabel("Open MacSweep")
            }
            Group {
                switch tab {
                case .system: NotchSystemTab()
                case .apps: NotchAppsTab(onQuit: quit)
                case .ports: NotchPortsTab(onQuit: quit)
                case .ai: NotchAITab(open: open)
                case .clean: NotchCleanTab(open: open)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.top, topInset + 8)
        .padding(.bottom, 16)
    }

    private func open(_ section: SidebarSection) {
        app.section = section
        app.openMainWindow?()
    }

    private func quit(_ pid: Int32, _ name: String) {
        _ = ProcessKiller.send(SIGTERM, to: pid, name: name)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await app.processes.refresh()
            await app.ports.refresh()
        }
    }
}

private struct NotchCleanTab: View {
    @Environment(AppModel.self) private var app
    let open: (SidebarSection) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RingGauge(value: app.monitor.volume.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0, label: "Disk used",
                      caption: app.monitor.volume.map { Format.bytes($0.available) + " free" }, size: 96, lineWidth: 10)
            VStack(alignment: .leading, spacing: 8) {
                Text(Format.bytes(app.cleanup.total(.safe))).font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("safe to clean · \(Format.bytes(app.cleanup.total(.review))) to review").foregroundStyle(.white.opacity(0.6))
                HStack {
                    Button { open(.storage) } label: { Label("Review & Clean", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent).tint(.green)
                    Button { app.disk.scan() } label: { Label(app.disk.isScanning ? "Scanning…" : "Rescan", systemImage: "arrow.clockwise") }
                        .disabled(app.disk.isScanning)
                }
                .controlSize(.small)
                if let result = app.disk.result {
                    Text("Last scan \(Format.relative(result.finishedAt))").foregroundStyle(.white.opacity(0.5))
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Biggest cleanable items").font(.caption).foregroundStyle(.white.opacity(0.55))
                let items = Array(app.cleanup.items.sorted { $0.size > $1.size }.prefix(6))
                let largest = Double(max(items.first?.size ?? 1, 1))
                if items.isEmpty { Text("Run a scan to see what can be cleaned.").foregroundStyle(.white.opacity(0.5)) }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.rule.title).lineLimit(1)
                            Spacer()
                            Text(Format.bytes(item.size)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                        }
                        GeometryReader { proxy in
                            Capsule().fill(item.rule.safety == .safe ? Color.green : .orange)
                                .frame(width: max(proxy.size.width * Double(item.size) / largest, 3))
                        }
                        .frame(height: 5)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
