import MacSweepCore
import SwiftUI

/// The Smart Scan landing page: greeting, one big Scan button, the four result cards and an overview of the Mac.
struct SmartScanHome: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appAccent) private var accent
    let onScan: () -> Void

    var body: some View {
        // The advisor walks every process, so it runs once here and the result is shared.
        let tips = Advisor.advise(app.advisorInput)
        let health = app.healthGrade(tips: tips.count)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 24) {
                hero(health)
                Spacer(minLength: 0)
                MacCard()
            }
            SmartScanResultCards(tips: tips)
            HStack(alignment: .top, spacing: 14) {
                WhatWeCheckCard().frame(maxWidth: .infinity)
                VStack(spacing: 14) {
                    MacHealthCard(grade: health)
                    ScanStorageCard()
                }
                .frame(width: 380)
            }
            ProTipsRow()
        }
    }

    private func hero(_ health: MacHealth) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(Self.greeting()), \(Self.firstName) 👋").font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(health == .needsAttention ? "Your Mac needs a little care," : "Your Mac looks good,")
                    .font(.system(size: 34, weight: .bold))
                Text(health == .needsAttention ? "let's sort it out together." : "but we can make it even better.")
                    .font(.system(size: 34, weight: .bold)).foregroundStyle(accent)
            }
            Text("Run a smart scan to find junk files, security issues, performance bottlenecks and more, all in one go.")
                .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 560, alignment: .leading)
            HStack(spacing: 18) {
                Button(action: onScan) {
                    Label("Scan My Mac", systemImage: "viewfinder")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Takes about 1 minute")
                        Text("Safe and read-only until you choose").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                } icon: { Image(systemName: "clock").font(.title2).foregroundStyle(.secondary) }
            }
            .padding(.top, 4)
        }
    }

    static var firstName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()
    }

    static func greeting(now: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<12: "Good Morning"
        case 12..<17: "Good Afternoon"
        default: "Good Evening"
        }
    }
}

/// Model, chip, macOS and memory, with a link to System Info.
private struct MacCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appAccent) private var accent

    var body: some View {
        let mac = app.system.mac
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "laptopcomputer").font(.system(size: 26)).foregroundStyle(accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mac.modelName).font(.headline)
                    Text(mac.chip).font(.callout).foregroundStyle(.secondary)
                }
            }
            Label(mac.osVersion.hasPrefix("macOS") ? mac.osVersion : "macOS \(mac.osVersion)", systemImage: "apple.logo").font(.callout)
            Label("\(Format.memory(mac.memory)) Unified Memory", systemImage: "memorychip").font(.callout)
            Button { app.section = .systemInfo } label: { Label("System Info", systemImage: "arrow.right").labelStyle(.titleAndIcon) }
                .buttonStyle(.link)
        }
        .padding(18)
        .frame(width: 280, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}
