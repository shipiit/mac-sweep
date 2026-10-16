import MacSweepCore
import SwiftUI

struct DeveloperHubView: View {
    @State private var model = DeveloperModel()
    @State private var tab: DevTab = .overview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    PillTabs(tabs: DevTab.allCases, selection: $tab, title: \.rawValue, symbol: \.symbol, badge: badge)
                    Spacer()
                    Button { Task { await model.refresh(tab) } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh").accessibilityLabel("Refresh").disabled(model.state(tab).isLoading)
                }
                if let busy = model.busy {
                    Label("\(busy)…", systemImage: "hourglass").font(.callout).foregroundStyle(.secondary)
                }
                if case .failed(let message) = model.state(tab) {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if model.state(tab).isLoading && tab != .overview { DevLoadingCard(tab: tab) }
                content
            }
            .padding(20)
        }
        .navigationTitle("Developer")
        .task(id: tab) { await model.loadIfNeeded(tab) }
        .alert(model.confirmation?.action.title ?? "", isPresented: Binding(get: { model.confirmation != nil }, set: { if !$0 { model.confirmation = nil } }),
               presenting: model.confirmation) { confirmation in
            Button(confirmation.action.buttonTitle, role: .destructive) { Task { await model.perform(confirmation.action) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text($0.action.message) }
        .alert("Developer", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.notice ?? "") }
    }

    private func badge(_ tab: DevTab) -> String? {
        switch tab {
        case .homebrew: model.brew.map { $0.outdated.isEmpty ? nil : "\($0.outdated.count)" } ?? nil
        case .nodeModules: model.nodeProjects.isEmpty ? nil : "\(model.nodeProjects.count)"
        case .services: model.services.isEmpty ? nil : "\(model.services.filter { $0.state == .running }.count)/\(model.services.count)"
        case .runtimes: model.runtimes.isEmpty ? nil : "\(model.runtimes.count)"
        default: nil
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .overview: DevOverview(model: model) { tab = $0 }
        case .docker: DockerSection(model: model)
        case .homebrew: BrewSection(model: model)
        case .runtimes: RuntimesSection(model: model)
        case .xcode: XcodeSection(model: model)
        case .nodeModules: NodeModulesSection(model: model)
        case .services: ServicesSection(model: model)
        }
    }
}

/// Friendly scanning state with what is being looked at.
private struct DevLoadingCard: View {
    let tab: DevTab
    @Environment(\.appAccent) private var accent

    var body: some View {
        HStack(spacing: 16) {
            SpinningRing(isActive: true, lineWidth: 4).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(tab == .nodeModules ? "Scanning all your projects…" : "Loading \(tab.rawValue)…").font(.headline)
                Text(tab == .nodeModules ? "Looking through your home folder for node_modules and measuring each one."
                     : "Asking \(tab.rawValue) for its current state.").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// One card per area with its headline number; clicking opens the tab.
private struct DevOverview: View {
    let model: DeveloperModel
    let open: (DevTab) -> Void

    var body: some View {
        EqualHeightGrid(items: DevTab.allCases.filter { $0 != .overview }, columns: 3) { tab in
            Button { open(tab) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label(tab.rawValue, systemImage: tab.symbol).font(.headline)
                    Text(headline(tab)).font(.system(size: 26, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(detail(tab)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.5)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func headline(_ tab: DevTab) -> String {
        if model.state(tab).isLoading { return "…" }
        switch tab {
        case .docker:
            if case .ready(let usage) = model.docker { return Format.bytes(usage.totalSize) }
            return model.docker == .notInstalled ? "Not installed" : model.docker == .notRunning ? "Not running" : "—"
        case .homebrew: return model.brew.map { "\($0.outdated.count) outdated" } ?? "—"
        case .runtimes: return "\(model.runtimes.count) versions"
        case .xcode: return Format.bytes(model.xcodeLocations.reduce(0) { $0 + ($1.size ?? 0) })
        case .nodeModules: return Format.bytes(model.nodeProjects.reduce(0) { $0 + $1.totalSize })
        case .services: return "\(model.services.filter { $0.state == .running }.count) running"
        case .overview: return ""
        }
    }

    private func detail(_ tab: DevTab) -> String {
        switch tab {
        case .docker:
            if case .ready(let usage) = model.docker { return "\(Format.bytes(usage.totalReclaimable)) reclaimable" }
            return "Images, containers, volumes and build cache"
        case .homebrew: return model.brew.map { "\(Format.bytes($0.cleanup.reclaimable)) to clean up" } ?? "Outdated packages and old downloads"
        case .runtimes: return "Node, Python and Ruby installs · \(model.globalPackages.count) global packages"
        case .xcode: return "DerivedData, archives, device support · \(model.simulators.count) simulators"
        case .nodeModules: return "\(model.nodeProjects.count) projects"
        case .services: return "\(model.services.count) dev services (Postgres, Redis…)"
        case .overview: return ""
        }
    }
}
