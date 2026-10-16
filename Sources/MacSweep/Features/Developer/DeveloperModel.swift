import Foundation
import MacSweepCore
import Observation

/// State for the Developer hub. Each section loads once, on first view, and again only on Refresh.
@MainActor
@Observable
final class DeveloperModel {
    let home: String

    private(set) var states: [DevTab: DevSectionState] = [:]
    private(set) var docker: DockerStatus?
    private(set) var brew: BrewSnapshot?
    private(set) var runtimes: [RuntimeVersion] = []
    private(set) var globalPackages: [GlobalPackage] = []
    private(set) var xcodeLocations: [XcodeLocation] = []
    private(set) var simulators: [Simulator] = []
    private(set) var simulatorError: String?
    var nodeProjects: [NodeProject] = []
    private(set) var services: [DevService] = []
    private(set) var servicesError: String?

    /// The action currently running, so its button can show progress and others stay disabled.
    var busy: String?
    /// Outcome of the last action, shown once in an alert.
    var notice: String?
    var confirmation: DevConfirmation?

    init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    func state(_ tab: DevTab) -> DevSectionState { states[tab] ?? .idle }

    /// Loads a tab the first time it's shown; node_modules scans the home folder in the background.
    func loadIfNeeded(_ tab: DevTab) async {
        switch tab {
        case .overview:
            await loadConcurrently(Self.overviewSections.filter { state($0) == .idle })
        default:
            if state(tab) == .idle { await load(tab) }
        }
    }

    func refresh(_ tab: DevTab) async {
        if tab == .overview {
            await loadConcurrently(Self.overviewSections)
        } else {
            await load(tab)
        }
    }

    private static let overviewSections: [DevTab] = [.docker, .homebrew, .xcode, .runtimes]

    private func loadConcurrently(_ tabs: [DevTab]) async {
        await withTaskGroup(of: Void.self) { group in
            for tab in tabs { group.addTask { await self.load(tab) } }
        }
    }

    func load(_ tab: DevTab) async {
        guard !state(tab).isLoading else { return }
        states[tab] = .loading
        switch tab {
        case .overview: states[tab] = .loaded
        case .docker: await loadDocker()
        case .homebrew: await loadBrew()
        case .runtimes: await loadRuntimes()
        case .xcode: await loadXcode()
        case .nodeModules: await scanNodeModules()
        case .services: await loadServices()
        }
    }

    private func loadDocker() async {
        docker = await DockerClient.status(home: home)
        states[.docker] = .loaded
    }

    private func loadBrew() async {
        do {
            brew = try await Homebrew.snapshot()
            states[.homebrew] = .loaded
        } catch {
            brew = nil
            states[.homebrew] = .failed(error.localizedDescription)
        }
    }

    private func loadRuntimes() async {
        let home = home
        let found = await Task.detached(priority: .utility) {
            let versions = RuntimeInventory.versions(home: home)
            return (versions, RuntimeInventory.allGlobalPackages(home: home, versions: versions))
        }.value
        runtimes = found.0
        globalPackages = found.1
        states[.runtimes] = .loaded
        let sizes = await Self.measure(found.0.map(\.path))
        runtimes = runtimes.map { version in
            var copy = version
            copy.size = sizes[version.path] ?? 0
            return copy
        }
    }

    private func loadXcode() async {
        let home = home
        let locations = await Task.detached(priority: .utility) {
            XcodeStorage.locations(home: home).map { location in
                var copy = location
                copy.itemCount = XcodeStorage.children(of: location.path).count
                return copy
            }
        }.value
        xcodeLocations = locations
        do {
            simulators = try await XcodeStorage.simulators()
            simulatorError = nil
        } catch {
            simulators = []
            simulatorError = error.localizedDescription
        }
        states[.xcode] = .loaded
        let sizes = await Self.measure(locations.map(\.path))
        xcodeLocations = xcodeLocations.map { location in
            var copy = location
            copy.size = sizes[location.path] ?? 0
            return copy
        }
    }

    private func scanNodeModules() async {
        let home = home
        let projects = await Task.detached(priority: .utility) {
            let folders = NodeModulesFinder.find(roots: NodeModulesFinder.defaultRoots(home: home))
            let grouped = NodeModulesFinder.group(folders, gitRoots: NodeModulesFinder.gitRoots(for: folders))
            return grouped.map { project in
                var copy = project
                copy.lastModified = NodeModulesFinder.lastModified(project: project.root)
                return copy
            }
        }.value
        nodeProjects = projects
        states[.nodeModules] = .loaded
        let sizes = await Self.measure(projects.flatMap { $0.folders.map(\.path) })
        nodeProjects = NodeModulesFinder.sorted(nodeProjects.map { project in
            var copy = project
            copy.folders = project.folders.map { NodeModulesFolder(path: $0.path, size: sizes[$0.path] ?? 0) }
            return copy
        })
    }

    private func loadServices() async {
        let result = await DevServiceControl.list(home: home)
        services = result.services
        servicesError = result.error
        states[.services] = .loaded
    }

    /// Measures folders a few at a time on background threads; one result per path.
    nonisolated static func measure(_ paths: [String]) async -> [String: UInt64] {
        let limiter = AsyncLimiter(limit: 3)
        return await withTaskGroup(of: (String, UInt64).self) { group in
            for path in paths {
                group.addTask {
                    await limiter.acquire()
                    let size = await Task.detached(priority: .utility) { DiskScanner.measure(path) ?? 0 }.value
                    await limiter.release()
                    return (path, size)
                }
            }
            var sizes: [String: UInt64] = [:]
            for await (path, size) in group { sizes[path] = size }
            return sizes
        }
    }
}
