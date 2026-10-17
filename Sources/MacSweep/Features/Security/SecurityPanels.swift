import MacSweepCore
import SwiftUI

/// One card per built-in protection, with its real state and a fix button when it's off.
struct ProtectionCards: View {
    let checks: [ProtectionCheck]
    @Environment(AppModel.self) private var app
    @State private var error: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if checks.isEmpty {
                ForEach(0..<5, id: \.self) { _ in Panel { SkeletonBar().frame(height: 110) } }
            }
            ForEach(checks) { check in card(check) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .alert("Couldn't turn it on", isPresented: isPresented($error), presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0) }
    }

    private func card(_ check: ProtectionCheck) -> some View {
        let isOn = check.state == .on
        let tint: Color = isOn ? .green : check.state == .off ? .red : .secondary
        return Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    IconBadge(symbol: symbol(check.id), tint: tint, size: 36)
                    Text(check.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                }
                Text(check.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    Label(check.id == "xprotect" && isOn ? "Up to date" : isOn ? "On" : check.state == .off ? "Off" : "Unknown", systemImage: "circle.fill")
                        .font(.callout.weight(.semibold)).foregroundStyle(tint).imageScale(.small)
                    Spacer()
                    if check.state == .off {
                        if check.id == "firewall" {
                            Button("Turn On") { enableFirewall() }.controlSize(.small)
                        } else if let url = check.settingsURL.flatMap(URL.init(string:)) {
                            Button("Open Settings") { FileActions.open(url: url) }.controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func enableFirewall() {
        Task {
            do {
                try await AdminRunner.enableFirewall()
            } catch AdminRunner.AdminError.cancelled {
                return
            } catch {
                self.error = error.localizedDescription
            }
            await app.security.run()
        }
    }

    private func symbol(_ id: String) -> String {
        switch id {
        case "sip": "checkmark.shield.fill"
        case "gatekeeper": "lock.app.dashed"
        case "filevault": "lock.fill"
        case "firewall": "flame.fill"
        case "xprotect": "allergens.fill"
        default: "shield"
        }
    }
}

struct SecurityActivityCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let security = app.security
        let threats = app.threats
        FeatureCard(title: "Recent security activity", symbol: "clock", tint: .blue, subtitle: "What MacSweep checked and changed recently.") {
            VStack(alignment: .leading, spacing: 12) {
                if let run = security.lastRun {
                    ActivityRow(symbol: "checkmark", tint: security.highFindings == 0 ? .green : .orange, title: "Security audit completed",
                                detail: security.highFindings == 0 ? "No issues found" : "\(security.highFindings) to review", date: run)
                }
                if let scan = threats.history.first {
                    ActivityRow(symbol: "magnifyingglass", tint: scan.isClean ? .green : .orange, title: "\(scan.kind.rawValue) completed",
                                detail: scan.isClean ? "No threats found" : "\(scan.threats) found", date: scan.date)
                }
                if let xprotect = threats.xprotect {
                    ActivityRow(symbol: "arrow.down", tint: .blue, title: "XProtect definitions updated", detail: "Version \(xprotect.version)", date: xprotect.updated)
                }
                ForEach(app.insights.recent.filter { $0.rule == .newStartupItem }.prefix(2)) { alert in
                    ActivityRow(symbol: "power", tint: .orange, title: alert.title, detail: alert.message, date: alert.date)
                }
                if security.lastRun == nil && threats.history.isEmpty {
                    ActivityRow(symbol: "hourglass", tint: .gray, title: "No checks yet", detail: "Run Security Audit to start", date: nil)
                }
            }
        }
    }
}

struct SecurityRecommendationsCard: View {
    @Environment(AppModel.self) private var app
    @State private var error: String?

    var body: some View {
        let list = SecurityAdvisor.recommendations(protections: app.security.protections, findings: app.security.highFindings,
                                                   highRiskExtensions: app.security.highAccessExtensions,
                                                   downloadProtection: app.threats.isProtectionOn)
        FeatureCard(title: "Security recommendations", symbol: "lightbulb.fill", tint: .yellow,
                    subtitle: list.isEmpty ? "Nothing to do. Your settings look good." : "\(list.count) thing\(list.count == 1 ? "" : "s") would make your Mac safer.") {
            VStack(alignment: .leading, spacing: 10) {
                if list.isEmpty {
                    Label("All recommended protections are on.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                ForEach(list.prefix(4)) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.severity == .high ? "exclamationmark.shield.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(item.severity == .high ? .red : .orange).font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).fontWeight(.semibold)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        Button(item.actionTitle) { perform(item.action) }.controlSize(.small)
                    }
                }
            }
        }
        .alert("Couldn't do that", isPresented: isPresented($error), presenting: error) { _ in Button("OK", role: .cancel) {} } message: { Text($0) }
    }

    private func perform(_ action: SecurityRecommendation.Action) {
        switch action {
        case .enableFirewall:
            Task {
                do { try await AdminRunner.enableFirewall() } catch AdminRunner.AdminError.cancelled { return } catch { self.error = error.localizedDescription }
                await app.security.run()
            }
        case .openSettings(let url): FileActions.open(url: URL(string: url))
        case .reviewExtensions: app.section = .extensions
        case .reviewFindings: app.section = .security
        case .enableDownloadProtection: app.threats.isProtectionOn = true
        }
    }
}

/// How many apps can use the camera, microphone, screen and all files, from the privacy database.
struct PrivacyAccessCard: View {
    @Environment(AppModel.self) private var app
    @State private var counts: [String: Int]?
    @State private var needsAccess = false

    private let services: [(key: String, title: String, symbol: String)] = [
        ("kTCCServiceCamera", "Camera", "camera.fill"), ("kTCCServiceMicrophone", "Microphone", "mic.fill"),
        ("kTCCServiceScreenCapture", "Screen Recording", "rectangle.dashed.badge.record"),
        ("kTCCServiceSystemPolicyAllFiles", "Full Disk Access", "folder.fill"),
    ]

    var body: some View {
        FeatureCard(title: "Privacy & app access", symbol: "lock.fill", tint: .blue, subtitle: "Apps allowed to use sensitive features.",
                    action: { app.section = .permissions }) {
            VStack(spacing: 8) {
                if needsAccess {
                    Label("Grant Full Disk Access to see which apps have these permissions.", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(services, id: \.key) { service in
                    Button { app.section = .permissions } label: {
                        HStack {
                            Image(systemName: service.symbol).frame(width: 22).foregroundStyle(.secondary)
                            Text(service.title)
                            Spacer()
                            Text(counts.map { "\($0[service.key] ?? 0) apps have access" } ?? "Checking…").font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        var allowed: [String: Set<String>] = [:]
        var blocked = false
        for database in TCCDatabase.allCases {
            switch await TCCReader.read(database) {
            case .entries(let entries):
                for entry in entries where entry.authorization.isGranted { allowed[entry.serviceKey, default: []].insert(entry.client.raw) }
            case .needsFullDiskAccess: blocked = true
            default: break
            }
        }
        counts = allowed.mapValues(\.count)
        needsAccess = blocked && allowed.isEmpty
    }
}
