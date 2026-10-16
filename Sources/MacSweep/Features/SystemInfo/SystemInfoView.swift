import MacSweepCore
import SwiftUI

/// Everything about this Mac on one page, About-This-Mac style, with copy on every value.
struct SystemInfoView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appAccent) private var accent
    @State private var showSerial = false
    @State private var copiedAll = false

    @ViewBuilder private func content(for section: InfoSection) -> some View {
        switch section {
        case .network: NetworkSection()
        case .storage: storage
        case .memory: memory
        case .battery: battery
        case .devices: devices
        case .security: security
        case .software: software
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                hero
                EqualHeightGrid(items: InfoSection.allCases) { section in
                    InfoCard(title: section.title, symbol: section.symbol, tint: section.tint) { content(for: section) }
                }
            }
            .padding(20)
        }
        .background(OverviewBackground())
        .navigationTitle("System Info")
        .toolbar {
            Button(copiedAll ? "Copied" : "Copy All", systemImage: copiedAll ? "checkmark" : "doc.on.doc") {
                FileActions.copy(SystemReport.text(app: app))
                copiedAll = true
            }
            .help("Copy a full system report (serial and public IP excluded)")
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await app.system.loadDetails() } }
        }
        .task {
            await app.system.loadDetails()
            if app.apps.apps.isEmpty { await app.apps.refresh() }
            if app.startup.items.isEmpty { await app.startup.refresh() }
        }
    }

    private var hero: some View {
        let mac = app.system.mac
        return HStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(accent)
                    .frame(width: 110, height: 110)
                Image(systemName: "macbook").font(.system(size: 54, weight: .light)).foregroundStyle(.white)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(mac.modelName).font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("\(mac.chip) · \(Format.memory(mac.memory)) · \(mac.osVersion)").font(.title3).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Pill(text: Host.current().localizedName ?? "This Mac")
                    Pill(text: "Up \(app.system.uptime)")
                    Pill(text: "\(ProcessInfo.processInfo.processorCount) cores")
                    Pill(text: mac.modelIdentifier)
                }
                if let serial = app.system.serial {
                    HStack(spacing: 6) {
                        Text("Serial").foregroundStyle(.secondary)
                        Text(showSerial ? serial : HardwareInfo.masked(serial)).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        Button(showSerial ? "Hide" : "Show") { showSerial.toggle() }.buttonStyle(.link)
                        Button { FileActions.copy(serial) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).help("Copy serial number").accessibilityLabel("Copy serial number")
                    }
                    .font(.callout)
                }
            }
            Spacer()
        }
        .padding(22)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }

    @ViewBuilder private var storage: some View {
        if let volume = app.monitor.volume {
            Meter(fraction: Double(volume.used) / Double(max(volume.total, 1)), color: .blue,
                  caption: "\(Format.bytes(volume.used)) used of \(Format.bytes(volume.total))")
            InfoRow(label: "Available", value: Format.bytes(volume.available))
            InfoRow(label: "Safe to clean", value: Format.bytes(app.cleanup.total(.safe)), color: .green)
            InfoRow(label: "Last scan", value: Format.relative(app.disk.result?.finishedAt), copyable: false)
        }
    }

    @ViewBuilder private var memory: some View {
        if let memory = app.processes.memory {
            Meter(fraction: Double(memory.used) / Double(max(memory.total, 1)), color: .purple,
                  caption: "\(Format.memory(memory.used)) used of \(Format.memory(memory.total))")
            InfoRow(label: "App memory", value: Format.memory(memory.app))
            InfoRow(label: "Wired", value: Format.memory(memory.wired))
            InfoRow(label: "Compressed", value: Format.memory(memory.compressed))
            InfoRow(label: "Swap", value: "\(Format.memory(memory.swapUsed)) of \(Format.memory(memory.swapTotal))")
            InfoRow(label: "Pressure", value: memory.pressure.rawValue, color: memory.pressure.color)
        }
    }

    @ViewBuilder private var battery: some View {
        if let battery = app.system.battery {
            Meter(fraction: Double(battery.percent) / 100, color: battery.percent < 20 ? .red : .green,
                  caption: "\(battery.percent)% · \(battery.isCharging ? "Charging" : battery.isPluggedIn ? "Plugged in" : "On battery")")
            InfoRow(label: "Health", value: battery.health.map { "\(Int(($0 * 100).rounded()))% of design capacity" } ?? "—")
            InfoRow(label: "Cycle count", value: battery.cycleCount.map(String.init) ?? "—")
            InfoRow(label: "Temperature", value: battery.temperatureCelsius.map { $0.formatted(.number.precision(.fractionLength(1))) + " °C" } ?? "—")
            InfoRow(label: "Adapter", value: battery.adapterWatts.map { "\($0) W" } ?? "Not connected")
        } else {
            Text("No battery. Runs on mains power.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var devices: some View {
        ForEach(NSScreen.screens, id: \.self) { screen in
            InfoRow(label: screen == NSScreen.screens.first ? "Main display" : "Display",
                    value: "\(screen.localizedName) · \(Int(screen.frame.width))×\(Int(screen.frame.height)) @\(Int(screen.backingScaleFactor))x")
        }
        ForEach(app.system.devices) { device in
            InfoRow(label: device.kind.rawValue, value: device.name + (device.detail.map { " · \($0)" } ?? ""))
        }
        if app.system.devices.isEmpty { InfoRow(label: "USB / Bluetooth", value: "None connected", copyable: false) }
    }

    @ViewBuilder private var security: some View {
        ForEach(app.security.protections) { check in
            InfoRow(label: check.title.replacingOccurrences(of: " malware definitions", with: ""),
                    value: check.state == .on ? "On" : check.state == .off ? "Off" : "Unknown",
                    color: check.state == .on ? .green : check.state == .off ? .red : .secondary, copyable: false)
        }
        InfoRow(label: "Score", value: "\(app.security.score)%", copyable: false)
    }

    @ViewBuilder private var software: some View {
        InfoRow(label: "macOS build", value: ProcessInfo.processInfo.operatingSystemVersionString)
        InfoRow(label: "Apps", value: "\(app.apps.apps.count) installed", copyable: false)
        InfoRow(label: "Startup items", value: "\(app.startup.items.count)", copyable: false)
        InfoRow(label: "Updates", value: app.updates.lastChecked == nil ? "Not checked" : "\(app.updates.updates.count) available", copyable: false)
        InfoRow(label: "Extensions", value: "\(app.security.uniqueExtensionCount) in browsers", copyable: false)
        InfoRow(label: "Processes", value: "\(app.processes.rows.count) running", copyable: false)
    }
}

struct InfoCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                Text(title).font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

enum InfoSection: String, CaseIterable, Identifiable {
    case network, storage, memory, battery, devices, security, software

    var id: String { rawValue }

    var title: String {
        switch self {
        case .network: "Network"
        case .storage: "Storage"
        case .memory: "Memory"
        case .battery: "Battery"
        case .devices: "Displays & devices"
        case .security: "Security"
        case .software: "Software"
        }
    }

    var symbol: String {
        switch self {
        case .network: "network"
        case .storage: "internaldrive"
        case .memory: "memorychip"
        case .battery: "battery.100percent.bolt"
        case .devices: "display"
        case .security: "checkmark.shield"
        case .software: "square.stack.3d.up"
        }
    }

    var tint: Color {
        switch self {
        case .network: .teal
        case .storage: .blue
        case .memory: .purple
        case .battery: .green
        case .devices: .orange
        case .security: .indigo
        case .software: .pink
        }
    }
}
