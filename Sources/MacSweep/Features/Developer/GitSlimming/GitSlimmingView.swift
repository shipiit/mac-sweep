import MacSweepCore
import SwiftUI

/// Content for the Developer page's Git tab: biggest `.git` folders and safe, history-preserving maintenance.
struct GitSlimmingView: View {
    @State private var model = GitSlimmingModel.shared
    @State private var showAll = false
    @State private var filter: GitRepoFilter = .all
    @State private var sort: GitRepoSort = .size
    @State private var search = ""
    @Environment(\.appAccent) private var accent

    private static let visibleLimit = 25

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .confirmationDialog(dialogTitle, isPresented: isConfirming, titleVisibility: .visible, presenting: model.pending) { request in
            Button(request.action.rawValue) { Task { await model.perform(request) } }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(Self.explanation(request.action))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            IconBadge(symbol: "arrow.triangle.branch", tint: accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Git repositories").font(.title3.weight(.semibold))
                Text("Finds repositories in your home folder and shows how much of each is history in .git.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if case .measuring(let done, let total) = model.phase {
                ProgressView(value: Double(done), total: Double(max(total, 1))).frame(width: 120)
                    .accessibilityLabel("Measured \(done) of \(total) repositories")
            } else if model.phase == .finding {
                ProgressView().controlSize(.small).accessibilityLabel("Looking for repositories")
            }
            Button {
                Task { await model.scan() }
            } label: {
                Label(model.phase == .idle ? "Scan" : "Rescan", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isScanning)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            Text("Scan to find the repositories whose history takes the most space.").foregroundStyle(.secondary)
        case .gitMissing:
            Label("Git isn't available. Install the Command Line Tools with `xcode-select --install`.", systemImage: "wrench.and.screwdriver")
                .foregroundStyle(.secondary)
        case .finding:
            Text("Looking for repositories…").foregroundStyle(.secondary)
        case .measuring, .finished:
            if model.repos.isEmpty {
                if model.phase == .finished {
                    Label("No git repositories found in your home folder.", systemImage: "checkmark.seal").foregroundStyle(.secondary)
                }
            } else {
                summary
                repoList
            }
        }
    }

    private var summary: some View {
        StatStrip {
            StatTile(title: ".git total", value: Format.bytes(model.totalGitSize), detail: "\(Format.count(model.repos.count)) repositories")
            StatTile(title: "Could compact", value: Format.count(model.compactCandidates.count),
                     detail: "loose objects or several packs", dot: model.compactCandidates.isEmpty ? .green : .orange)
            StatTile(title: "Uncommitted work", value: Format.count(model.dirtyCount), detail: "repositories with changes")
            StatTile(title: "LFS cache", value: Format.bytes(model.totalLFSSize),
                     detail: model.isLFSInstalled ? "git lfs installed" : "git lfs not installed")
        }
    }

    private var repoList: some View {
        let query = search.lowercased()
        let matching = sort.sorted(model.repos.filter { filter.includes($0) && (query.isEmpty || $0.path.lowercased().contains(query)) })
        let visible = showAll || !query.isEmpty || filter != .all ? matching : Array(matching.prefix(Self.visibleLimit))
        let largest = max(model.repos.compactMap(\.gitSize).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Search repositories", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Picker("Show", selection: $filter) {
                    ForEach(GitRepoFilter.allCases) { item in Text("\(item.rawValue) \(model.repos.filter { item.includes($0) }.count)").tag(item) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                Picker("Sort by", selection: $sort) { ForEach(GitRepoSort.allCases) { Text($0.rawValue).tag($0) } }.fixedSize()
            }
            VStack(spacing: 0) {
                ForEach(visible) { repo in
                    GitRepoRow(repo: repo, largest: largest, model: model)
                    if repo.id != visible.last?.id { Divider().padding(.leading, 40) }
                }
                if visible.isEmpty { Text("No repositories match.").foregroundStyle(.secondary).padding(16) }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
            if matching.count > visible.count || (showAll && filter == .all && query.isEmpty && model.repos.count > Self.visibleLimit) {
                Button(showAll ? "Show the biggest \(Self.visibleLimit)" : "Show all \(matching.count) repositories") { showAll.toggle() }
                    .buttonStyle(.link)
            }
            Text("Compact runs git gc and Prune LFS cache runs git lfs prune. Neither changes commits, branches, tags or your files.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } })
    }

    private var dialogTitle: String {
        guard let pending = model.pending else { return "" }
        return "\(pending.action.rawValue) \(pending.repo.name)?"
    }

    static func explanation(_ action: GitRepoAction) -> String {
        switch action {
        case .compact:
            "Runs git gc --prune=now: packs loose objects and removes unreachable ones. Commits, branches, stashes and reflogs are kept. Large repositories can take a few minutes."
        case .pruneLFS:
            "Runs git lfs prune: deletes local copies of LFS files that aren't checked out, aren't recent and are already pushed. They download again when needed."
        }
    }
}

extension GitSlimmingModel {
    /// One instance for the app's lifetime, so results stay when you switch pages; Rescan refreshes them.
    static let shared = GitSlimmingModel()
}
