import AppKit
import MacSweepCore
import SwiftUI

/// Small uppercase section label, like "WORKSPACE".
struct SidebarHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
    }
}

/// One of the developer's other apps: opens it when installed, otherwise its latest release page.
struct MoreAppRow: View {
    let name: String
    let detail: String
    let symbol: String
    let tint: Color
    /// Nil for apps that aren't installed Mac apps (a browser extension, for example).
    let bundleID: String?
    let releases: String

    var body: some View {
        let installed = bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        Button {
            if let installed { NSWorkspace.shared.openApplication(at: installed, configuration: .init()) }
            else { FileActions.open(url: URL(string: releases)) }
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let installed {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: installed.path)).resizable()
                    } else {
                        Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                    Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: installed == nil ? "arrow.down.circle" : "arrow.up.forward.app").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .help(installed == nil ? "Download \(name)" : "Open \(name)")
        .accessibilityLabel(installed == nil ? "Download \(name)" : "Open \(name)")
    }
}

/// Disk usage with what's cleanable, and a shortcut to free space.
struct SidebarStorageCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.appAccent) private var accent

    var body: some View {
        let volume = app.monitor.volume
        let total = Double(max(volume?.total ?? 1, 1))
        let used = Double(volume?.used ?? 0)
        let junk = min(Double(app.cleanup.total(.safe) + app.cleanup.total(.review)), used)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Storage", systemImage: "internaldrive").font(.callout.weight(.semibold))
                Spacer()
                Text(Format.bytes(volume?.used ?? 0)).font(.callout.weight(.semibold)).monospacedDigit()
            }
            Text("\(Format.bytes(volume?.available ?? 0)) free on this Mac").font(.caption).foregroundStyle(.secondary)
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    Rectangle().fill(.blue).frame(width: proxy.size.width * (used - junk) / total)
                    Rectangle().fill(.pink).frame(width: proxy.size.width * junk / total)
                    Rectangle().fill(.quaternary)
                }
                .clipShape(Capsule())
            }
            .frame(height: 7)
            VStack(alignment: .leading, spacing: 3) {
                legend(.blue, "In use", UInt64(max(used - junk, 0)))
                legend(.pink, "Cleanable", UInt64(junk))
                legend(.secondary, "Free", volume?.available ?? 0)
            }
            Button { app.section = .storage } label: {
                Text("Free Up Space").font(.callout.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func legend(_ color: Color, _ title: String, _ bytes: UInt64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(title).font(.caption)
            Spacer()
            Text(Format.bytes(bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
