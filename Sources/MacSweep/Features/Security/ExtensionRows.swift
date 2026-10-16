import AppKit
import MacSweepCore
import SwiftUI

extension ExtensionRisk {
    var color: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }
}

/// One extension installed in one or more browsers/profiles, shown as a single row.
struct ExtensionGroup: Identifiable {
    let name: String
    let installs: [BrowserExtension]

    var id: String { name.lowercased() }
    var primary: BrowserExtension { installs.max { $0.risk < $1.risk } ?? installs[installs.startIndex] }
    var risk: ExtensionRisk { primary.risk }
    var browsers: [String] { Array(Set(installs.map(\.browser))).sorted() }

    static func group(_ extensions: [BrowserExtension]) -> [ExtensionGroup] {
        Dictionary(grouping: extensions) { $0.name.lowercased() }
            .compactMap { _, installs in installs.first.map { ExtensionGroup(name: $0.name, installs: installs) } }
            .sorted { ($0.risk, $1.name.lowercased()) > ($1.risk, $0.name.lowercased()) }
    }
}

struct ExtensionGroupRow: View {
    let group: ExtensionGroup
    @State private var expanded = false

    var body: some View {
        let primary = group.primary
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack(spacing: 10) {
                    ExtensionIcon(path: primary.iconPath)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name).fontWeight(.medium).lineLimit(1)
                        HStack(spacing: 4) {
                            ForEach(group.browsers, id: \.self) { Pill(text: $0) }
                            if !primary.fromStore { Pill(text: "Sideloaded", color: .red) }
                            if !group.installs.contains(where: \.state.enabled) { Pill(text: "Disabled") }
                            if let active = group.installs.compactMap(\.state.lastActivity).max() {
                                Text("Active \(Format.relative(active))").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(primary.capabilities.prefix(3), id: \.self) { capability in
                            Text(capability.rawValue).font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary.opacity(0.6), in: Capsule())
                        }
                    }
                    Label(group.risk.title, systemImage: group.risk == .low ? "checkmark.shield" : "exclamationmark.shield")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(group.risk.color)
                        .frame(width: 80, alignment: .trailing)
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.name), \(group.risk.title) risk")

            if expanded { details(primary).transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .padding(.vertical, 6)
    }

    private func details(_ primary: BrowserExtension) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(primary.riskReasons, id: \.self) { reason in
                Label(reason, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(group.risk.color)
            }
            ForEach(primary.capabilities, id: \.self) { capability in
                HStack(alignment: .top, spacing: 6) {
                    Text(capability.rawValue).font(.callout.weight(.medium)).frame(width: 130, alignment: .leading)
                    Text(capability.explanation).font(.callout).foregroundStyle(.secondary)
                }
            }
            if primary.capabilities.isEmpty { Text("Only narrow permissions.").font(.callout).foregroundStyle(.secondary) }
            ForEach(group.installs) { install in
                HStack(spacing: 8) {
                    Text("\(install.browser) · \(install.profile)").fontWeight(.medium)
                    Text("v\(install.version)")
                    if let installed = install.state.installed { Text("Installed \(installed.formatted(date: .abbreviated, time: .omitted))") }
                    if let active = install.state.lastActivity { Text("Last active \(Format.relative(active))") }
                    Text(install.state.enabled ? "Enabled" : "Disabled").foregroundStyle(install.state.enabled ? .green : .secondary)
                    Spacer()
                    if install.managePage != nil {
                        ForEach(install.profile.components(separatedBy: ", "), id: \.self) { profile in
                            Button(install.profile.contains(",") ? "Remove from \(profile)…" : "Remove…") {
                                ExtensionActions.openManagePage(install, profile: profile)
                            }
                            .help("Opens \(install.browser) in \(profile) on this extension's page; click Remove extension there")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack {
                if let url = primary.storeURL { Button("View in Store") { FileActions.open(url: url) } }
                Button("Reveal Files") { FileActions.reveal(primary.path) }
                if primary.browser == "Safari" { Text("Remove Safari extensions by uninstalling their app.").font(.caption).foregroundStyle(.tertiary) }
            }
            .controlSize(.small)
        }
        .padding(.leading, 42)
    }
}

struct ExtensionIcon: View {
    let path: String?

    var body: some View {
        Group {
            if let path, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "puzzlepiece.extension.fill").resizable().scaledToFit().padding(4).foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}

enum ExtensionActions {
    /// Browsers own their extension state (integrity-protected) and offer no outside uninstall, so removal
    /// happens in the browser. Chromium browsers are opened in the profile that actually has the extension;
    /// otherwise the page opens in whichever profile was used last and the extension can't be found.
    static func openManagePage(_ item: BrowserExtension, profile: String) {
        guard let page = item.managePage,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: page.bundleID)
        else { return }
        var arguments = ["-na", appURL.path, "--args"]
        if item.browser != "Firefox" && item.browser != "Safari" {
            arguments.append("--profile-directory=\(profile)")
        }
        arguments.append(page.url)
        Task { _ = try? await Shell.run("/usr/bin/open", arguments) }
    }
}
