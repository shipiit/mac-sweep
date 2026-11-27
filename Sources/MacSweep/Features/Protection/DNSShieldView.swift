import MacSweepCore
import SwiftUI

/// Switches the whole Mac to a DNS service that refuses malware, scam and (optionally) adult sites.
struct DNSShieldView: View {
    @State private var model = DNSShieldModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                if let error = model.error {
                    NoticeBanner(symbol: "exclamationmark.triangle", title: "DNS wasn't changed", message: error, actionTitle: "Dismiss") { model.error = nil }
                }
                if model.usesTailscaleDNS {
                    NoticeBanner(symbol: "exclamationmark.triangle", title: "Tailscale is answering DNS right now",
                                 message: "While Tailscale's MagicDNS is on, lookups go through Tailscale instead of the filter. Set the same DNS servers in the Tailscale admin console, or turn MagicDNS off.")
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Choose a filter", subtitle: "Applied to every network on this Mac (Wi-Fi, Ethernet, tethering). macOS asks for your password once.")
                        ForEach(DNSShield.profiles) { profile in
                            ProfileRow(profile: profile, isActive: model.active == profile, isBlocking: model.active == profile ? model.isBlocking : nil,
                                       isBusy: model.isApplying || !model.hasLoaded) { Task { await model.turnOn(profile) } }
                            if profile != DNSShield.profiles.last { Divider() }
                        }
                    }
                }
                networks
                limits
            }
            .padding(20)
        }
        .task { await model.refresh() }
    }

    private var hero: some View {
        let active = model.active
        return SummaryHero(
            symbol: active == nil ? "shield.slash" : "shield.lefthalf.filled", eyebrow: "DNS filter",
            value: active?.title ?? "Off",
            caption: active.map { "\($0.provider) blocks: \($0.blocks)" + (model.isBlocking == true ? " Checked just now: a test site was refused." : model.isBlocking == false ? " A test site still loaded, so something is going around the filter." : "") }
                ?? (model.currentServers.isEmpty ? "This Mac uses your router's DNS, which blocks nothing." : "This Mac uses \(model.currentServers.prefix(2).joined(separator: ", ")), which blocks nothing."),
            tint: active == nil ? .orange : model.isBlocking == false ? .orange : .green, isLoading: !model.hasLoaded, segments: []
        ) {
            if active != nil || model.hasPrevious {
                Button { Task { await model.turnOff() } } label: { Label("Turn Off", systemImage: "arrow.uturn.backward").frame(minWidth: 120) }
                    .disabled(model.isApplying).help("Puts back the DNS servers this Mac had before")
            }
            Button { Task { await model.refresh() } } label: { Label("Recheck", systemImage: "arrow.clockwise").frame(minWidth: 120) }.disabled(model.isLoading)
        }
    }

    private var networks: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Your networks", subtitle: "What each one uses for DNS right now.")
                ForEach(model.services) { service in
                    HStack {
                        Text(service.service).font(.callout.weight(.medium))
                        Spacer()
                        Text(service.servers.isEmpty ? "From the router" : service.servers.joined(separator: ", "))
                            .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Pill(text: DNSShield.profile(for: service.servers)?.provider ?? "No filter",
                             color: DNSShield.profile(for: service.servers) == nil ? .secondary : .green)
                    }
                }
                if model.services.isEmpty && model.hasLoaded { Text("No network services found.").foregroundStyle(.secondary) }
            }
        }
    }

    private var limits: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "What this does and doesn't stop")
                Label("Known malware, phishing and scam sites fail to load in every app, before anything is downloaded.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                Label("A VPN sends lookups through its own servers, so the filter is skipped while one is connected.", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                Label("A browser with its own \"secure DNS\" switched on goes around it. Set Chrome, Brave or Firefox to use the system DNS.", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                Label("Anyone who knows your Mac password can turn it off here.", systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }
}

private struct ProfileRow: View {
    let profile: DNSProfile
    let isActive: Bool
    let isBlocking: Bool?
    let isBusy: Bool
    let turnOn: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(isActive ? .green : .secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(profile.title).font(.callout.weight(.semibold))
                    Text(profile.provider).font(.caption).foregroundStyle(.secondary)
                    if isBlocking == true { Pill(text: "Verified blocking", color: .green) }
                    if isBlocking == false { Pill(text: "Being bypassed", color: .orange) }
                }
                Text(profile.blocks).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(profile.servers.prefix(2).joined(separator: " · ")).font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            if isActive { Pill(text: "On", color: .green) } else { Button("Turn On", action: turnOn).disabled(isBusy) }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
