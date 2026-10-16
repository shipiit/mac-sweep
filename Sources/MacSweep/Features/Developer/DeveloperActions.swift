import Foundation
import MacSweepCore

/// Destructive work runs only from a confirmed `DevConfirmation`; file removals go through `Cleaner` (PathGuard + Trash).
extension DeveloperModel {
    func ask(_ action: DevPendingAction) {
        confirmation = DevConfirmation(action: action)
    }

    func perform(_ action: DevPendingAction) async {
        busy = action.title
        defer { busy = nil }
        do {
            switch action {
            case .dockerPrune(let kind, _):
                let freed = try await DockerClient.prune(kind)
                notice = "Docker freed \(Format.bytes(freed))."
                await refresh(.docker)
            case .brewCleanup:
                try await Homebrew.runCleanup()
                notice = "Homebrew cleanup finished."
                await refresh(.homebrew)
            case .deleteUnavailableSimulators:
                try await XcodeStorage.deleteUnavailableSimulators()
                notice = "Unavailable simulators deleted."
                await refresh(.xcode)
            case .trash(let paths, let title, _):
                let home = home
                let targets = paths.map { CleanupTarget(path: $0, size: 0) }
                let results = await Task.detached(priority: .userInitiated) { Cleaner.remove(targets, mode: .trash, home: home) }.value
                let failed = results.filter { !$0.succeeded }
                notice = failed.isEmpty ? "Moved \(title) to the Trash." : "\(failed.count) item(s) couldn't be moved: \(failed.first.map { Format.path($0.path) } ?? "")"
                let removed = Set(results.filter(\.succeeded).map(\.path))
                nodeProjects = nodeProjects.compactMap { project in
                    var copy = project
                    copy.folders.removeAll { removed.contains($0.path) }
                    return copy.folders.isEmpty ? nil : copy
                }
                await refresh(.xcode)
            }
        } catch {
            notice = error.localizedDescription
        }
    }

    func perform(_ action: DevServiceAction, on service: DevService) async {
        busy = "\(action.rawValue) \(service.name)"
        defer { busy = nil }
        do {
            try await DevServiceControl.perform(action, on: service)
            try? await Task.sleep(for: .milliseconds(600))
            await refresh(.services)
        } catch {
            notice = "Couldn't \(action.rawValue.lowercased()) \(service.name): \(error.localizedDescription)"
        }
    }
}
