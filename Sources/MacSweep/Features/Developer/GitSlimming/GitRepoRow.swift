import MacSweepCore
import SwiftUI

/// One-line repository row; expands into the full card with object counts and every action.
struct GitRepoRow: View {
    let repo: GitRepoInfo
    let largest: UInt64
    let model: GitSlimmingModel
    @State private var isExpanded = false
    @Environment(\.appAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { isExpanded.toggle() } label: {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0)).frame(width: 14)
                }
                .buttonStyle(.plain).accessibilityLabel(isExpanded ? "Hide details" : "Show details")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(repo.name).fontWeight(.semibold).lineLimit(1)
                        if repo.hasUncommittedWork == true { Pill(text: "Uncommitted", color: .orange) }
                        if repo.isInUse { Pill(text: "In use", color: .secondary) }
                        if repo.lfsSize > 0 { Pill(text: "LFS", color: .blue) }
                    }
                    Text(Format.path(repo.path) + (repo.lastCommit.map { " · last commit \(Format.relative($0))" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                .frame(minWidth: 220, alignment: .leading)
                Spacer(minLength: 8)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary.opacity(0.5))
                        Capsule().fill(accent.opacity(0.75)).frame(width: max(proxy.size.width * Double(repo.gitSize ?? 0) / Double(max(largest, 1)), 2))
                    }
                }
                .frame(width: 140, height: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(repo.gitSize.map(Format.bytes) ?? "…").font(.callout.weight(.semibold)).monospacedDigit()
                    Text(repo.gitShare.map { "\(Int(($0 * 100).rounded()))% history" } ?? " ").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 90, alignment: .trailing)
                if let running = model.running[repo.path] {
                    ProgressView().controlSize(.small).help("\(running.rawValue)…")
                } else {
                    Button("Compact") { model.ask(.compact, for: repo) }
                        .controlSize(.small).disabled(repo.isInUse || model.isScanning)
                }
                Menu {
                    Button("Reveal in Finder") { FileActions.reveal(repo.path) }
                    Button("Copy Path") { FileActions.copy(repo.path) }
                    if model.isLFSInstalled, repo.lfsSize > 0 { Button("Prune LFS cache") { model.ask(.pruneLFS, for: repo) } }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More actions for \(repo.name)")
            }
            if let outcome = model.outcomes[repo.path] {
                Label(outcome, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green).padding(.leading, 26)
            }
            if isExpanded {
                GitRepoCard(repo: repo, largest: largest, running: model.running[repo.path], outcome: nil,
                            isLFSInstalled: model.isLFSInstalled, isBusy: model.isScanning) { action in model.ask(action, for: repo) }
                    .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

enum GitRepoFilter: String, CaseIterable, Identifiable {
    case all = "All", compactable = "Can compact", uncommitted = "Uncommitted", stale = "Untouched 90d+"
    var id: String { rawValue }

    func includes(_ repo: GitRepoInfo, now: Date = Date()) -> Bool {
        switch self {
        case .all: true
        case .compactable: repo.objects?.wouldBenefitFromCompact == true
        case .uncommitted: repo.hasUncommittedWork == true
        case .stale: repo.lastCommit.map { now.timeIntervalSince($0) > 90 * 86_400 } ?? false
        }
    }
}

enum GitRepoSort: String, CaseIterable, Identifiable {
    case size = ".git size", share = "History share", recent = "Last commit", name = "Name"
    var id: String { rawValue }

    func sorted(_ repos: [GitRepoInfo]) -> [GitRepoInfo] {
        switch self {
        case .size: repos.sorted { ($0.gitSize ?? 0) > ($1.gitSize ?? 0) }
        case .share: repos.sorted { ($0.gitShare ?? 0) > ($1.gitShare ?? 0) }
        case .recent: repos.sorted { ($0.lastCommit ?? .distantPast) > ($1.lastCommit ?? .distantPast) }
        case .name: repos.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
}
