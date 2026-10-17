import MacSweepCore
import SwiftUI

extension AppModel {
    var freeFraction: Double {
        monitor.volume.map { Double($0.available) / Double(max($0.total, 1)) } ?? 1
    }

    func healthGrade(tips: Int) -> MacHealth {
        MacHealth.grade(securityScore: security.score, highFindings: security.highFindings, tips: tips, freeFraction: freeFraction)
    }
}

/// Tinted card with an icon badge, headline, a meter and a coloured action button.
struct TintedCard: View {
    let title: String
    let symbol: String
    let tint: Color
    let headline: String
    let detail: String
    /// 0...1 fill for the meter; nil hides it.
    let meter: Double?
    let action: (title: String, run: () -> Void)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                Text(title).font(.headline).foregroundStyle(tint)
            }
            Text(headline).font(.system(size: 30, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            if let meter {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.15))
                        Capsule().fill(tint).frame(width: proxy.size.width * min(max(meter, 0), 1))
                    }
                }
                .frame(height: 6)
            }
            Spacer(minLength: 0)
            Button(action: action.run) {
                Label(action.title, systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle())
                    .font(.callout.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.35)))
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.title; configuration.icon }
    }
}

struct SmartScanResultCards: View {
    @Environment(AppModel.self) private var app
    let tips: [Advice]

    var body: some View {
        let safe = app.cleanup.total(.safe)
        let review = app.cleanup.total(.review)
        HStack(spacing: 14) {
            TintedCard(title: "Junk Files", symbol: "trash.fill", tint: .green, headline: Format.bytes(safe),
                       detail: "Safe to remove · \(Format.bytes(review)) to review",
                       meter: safe + review > 0 ? Double(safe) / Double(safe + review) : 0,
                       action: ("Review & Clean", { app.cleanup.selectSafe(); app.section = .storage }))
            TintedCard(title: "Protection", symbol: "checkmark.shield.fill", tint: .indigo, headline: "\(app.security.score)%",
                       detail: "\(app.security.highFindings) to review · \(app.security.protectionsOff) protection\(app.security.protectionsOff == 1 ? "" : "s") off",
                       meter: Double(app.security.score) / 100, action: ("Review", { app.section = .security }))
            TintedCard(title: "Performance", symbol: "gauge.with.dots.needle.67percent", tint: .orange,
                       headline: tips.isEmpty ? "All good" : "\(tips.count) tip\(tips.count == 1 ? "" : "s")",
                       detail: tips.first?.title ?? "Nothing slowing your Mac down", meter: nil,
                       action: ("Optimize", { app.section = .optimization }))
            TintedCard(title: "Applications", symbol: "square.stack.3d.up.fill", tint: .purple,
                       headline: app.updates.lastChecked == nil ? "Not checked" : "\(app.updates.updates.count) update\(app.updates.updates.count == 1 ? "" : "s")",
                       detail: app.apps.orphans.isEmpty ? "No leftovers from deleted apps" : "\(app.apps.orphans.count) leftovers from deleted apps",
                       meter: nil, action: ("Manage", { app.section = app.updates.updates.isEmpty ? .uninstaller : .updater }))
        }
    }
}

struct WhatWeCheckCard: View {
    private let checks: [(String, String, String, Color)] = [
        ("trash.fill", "System Junk", "Caches, logs, temporary files", .green),
        ("square.stack.3d.up.fill", "Applications", "Uninstaller, leftovers, updates", .orange),
        ("checkmark.shield.fill", "Security", "Malware, vulnerabilities, privacy", .indigo),
        ("doc.fill", "Large & Old Files", "Find and remove space hogs", .pink),
        ("gauge.with.dots.needle.67percent", "Performance", "Login items, heavy processes", .purple),
        ("doc.on.doc.fill", "Duplicates", "Photos, documents, downloads", .teal),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("What we'll check", systemImage: "sparkles").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
                ForEach(checks, id: \.1) { symbol, title, detail, tint in
                    HStack(spacing: 12) {
                        Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
                            .frame(width: 42, height: 42).background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).fontWeight(.semibold)
                            Text(detail).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

struct MacHealthCard: View {
    @Environment(AppModel.self) private var app
    let grade: MacHealth

    var body: some View {
        let tint: Color = grade == .needsAttention ? .orange : .green
        Button { app.section = .overview } label: {
            HStack(spacing: 14) {
                Image(systemName: grade == .needsAttention ? "heart.text.square.fill" : "heart.fill").font(.title2).foregroundStyle(tint)
                    .frame(width: 46, height: 46).background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac Health").font(.callout).foregroundStyle(.secondary)
                    Text(grade.rawValue).font(.title3.weight(.bold)).foregroundStyle(tint)
                    Text(grade.summary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ScanStorageCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let volume = app.monitor.volume
        let total = Double(max(volume?.total ?? 1, 1))
        let used = Double(volume?.used ?? 0)
        let junk = Double(app.cleanup.total(.safe) + app.cleanup.total(.review))
        Button { app.section = .storage } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "internaldrive.fill").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Storage Overview").font(.headline)
                        Text("\(Format.bytes(volume?.used ?? 0)) of \(Format.bytes(volume?.total ?? 0)) used").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        Capsule().fill(.blue).frame(width: proxy.size.width * max(used - junk, 0) / total)
                        Capsule().fill(.orange).frame(width: proxy.size.width * min(junk, used) / total)
                        Capsule().fill(.quaternary)
                    }
                }
                .frame(height: 8)
                HStack(spacing: 14) {
                    legend("In use", .blue, max(used - junk, 0))
                    legend("Cleanable", .orange, min(junk, used))
                    legend("Free", .secondary, Double(volume?.available ?? 0))
                }
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func legend(_ title: String, _ color: Color, _ bytes: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(title, systemImage: "circle.fill").font(.caption).foregroundStyle(color).labelStyle(.titleAndIcon)
            Text(Format.bytes(UInt64(bytes))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

struct ProTipsRow: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pro Tips", systemImage: "lightbulb.fill").font(.headline).foregroundStyle(.yellow)
            HStack(spacing: 12) {
                tip("externaldrive.fill", .green, "Keep at least 15% free storage", "For better performance.") { app.section = .storage }
                tip("arrow.clockwise", .blue, "Restart occasionally", "Up \(app.system.uptime): clears memory and updates.") { app.section = .systemInfo }
                tip("arrow.down.app.fill", .purple, "Keep apps updated", "For the latest features and security.") { app.section = .updater }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }

    private func tip(_ symbol: String, _ tint: Color, _ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(.white).frame(width: 36, height: 36).background(tint, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.semibold).lineLimit(1)
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
