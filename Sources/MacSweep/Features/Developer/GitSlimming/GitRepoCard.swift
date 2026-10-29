import AppKit
import MacSweepCore
import SwiftUI

/// One repository: `.git` versus working tree, git's object counts, state pills and the per-repo actions.
struct GitRepoCard: View {
    let repo: GitRepoInfo
    let largest: UInt64
    let running: GitRepoAction?
    let outcome: String?
    let isLFSInstalled: Bool
    let isBusy: Bool
    let onAction: (GitRepoAction) -> Void
    @Environment(\.appAccent) private var accent

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(symbol: "shippingbox", tint: accent, size: 32)
                    titleBlock
                    Spacer(minLength: 12)
                    sizeBlock
                }
                bar
                details
                if let running {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(running == .compact ? "Compacting…" : "Pruning LFS cache…").font(.callout).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } else if let outcome {
                    Label(outcome, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
                }
                actions
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(repo.name).fontWeight(.semibold)
                if repo.isInUse { Pill(text: "In use", color: .orange) }
                if repo.hasUncommittedWork == true { Pill(text: "Uncommitted changes", color: .orange) }
                if repo.lfsSize > 0 { Pill(text: "LFS \(Format.bytes(repo.lfsSize))", color: accent) }
            }
            Text(Format.path(repo.path)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Text(repo.lastCommit.map { "Last commit \(Format.relative($0))" } ?? (repo.isInUse ? "Skipped while another git process runs" : "No commits"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var sizeBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(repo.gitSize == nil ? "Measuring…" : Format.bytes(repo.gitSize))
                .font(.system(.title3, design: .monospaced).weight(.semibold))
            Text("in .git").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var bar: some View {
        GeometryReader { proxy in
            Capsule().fill(accent.opacity(0.7))
                .frame(width: max(proxy.size.width * Double(repo.gitSize ?? 0) / Double(max(largest, 1)), 3))
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var details: some View {
        HStack(spacing: 18) {
            metric("Working tree", Format.bytes(repo.workingTreeSize))
            metric("History share", repo.gitShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
            if let objects = repo.objects {
                metric("Loose objects", "\(Format.count(objects.looseCount)) · \(Format.bytes(objects.looseSize))")
                metric("Packs", "\(Format.count(objects.packs)) · \(Format.bytes(objects.packSize))")
                if objects.garbageCount > 0 { metric("Garbage", "\(Format.count(objects.garbageCount)) · \(Format.bytes(objects.garbageSize))") }
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.callout, design: .monospaced))
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { onAction(.compact) } label: { Label("Compact", systemImage: "archivebox") }
                .disabled(isLocked)
                .help(repo.isInUse ? "Another git process is using this repository" : "Run git gc --prune=now")
            if isLFSInstalled && repo.lfsSize > 0 {
                Button { onAction(.pruneLFS) } label: { Label("Prune LFS cache", systemImage: "scissors") }
                    .disabled(isLocked)
            }
            Spacer()
            Button { FileActions.reveal(repo.path) } label: { Label("Reveal", systemImage: "folder") }
                .buttonStyle(.borderless)
            Button { TerminalLauncher.open(repo.path) } label: { Label("Open in Terminal", systemImage: "terminal") }
                .buttonStyle(.borderless)
        }
        .controlSize(.small)
    }

    private var isLocked: Bool { running != nil || isBusy || repo.isInUse || repo.gitSize == nil }
}

enum TerminalLauncher {
    static func open(_ path: String) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            FileActions.reveal(path)
            return
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: path, isDirectory: true)], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}
