import Foundation
import MacSweepCore
import Observation

@MainActor
@Observable
final class StartupModel {
    enum Status: Equatable {
        case running(Int32)
        case loaded
        case failed(Int32)
        case disabled
        case notLoaded

        var title: String {
            switch self {
            case .running(let pid): "Running · \(pid)"
            case .loaded: "Loaded"
            case .failed(let code): "Exited \(code)"
            case .disabled: "Disabled"
            case .notLoaded: "Not loaded"
            }
        }
    }

    private(set) var items: [LaunchItem] = []
    private(set) var state = LaunchState.empty
    private(set) var isLoading = false
    private(set) var busyItem: String?
    var error: String?

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        async let scanned = Task.detached { LaunchItemScanner.scan() }.value
        async let launchState = LaunchControl.readState()
        (items, state) = await (scanned, launchState)
    }

    /// launchctl only reports the user domain without root, so daemons show "Not loaded" unless running.
    func status(of item: LaunchItem) -> Status {
        if item.disabledInPlist || state.disabled.contains(item.label) { return .disabled }
        guard let status = state.statuses[item.label] else { return .notLoaded }
        if let pid = status.pid { return .running(pid) }
        if let code = status.lastExitStatus, code != 0 { return .failed(code) }
        return .loaded
    }

    func perform(_ action: LaunchAction, on item: LaunchItem) async {
        busyItem = item.id
        defer { busyItem = nil }
        do {
            try await LaunchControl.perform(action, on: item)
        } catch AdminRunner.AdminError.cancelled {
            return
        } catch {
            self.error = "\(action.rawValue) \(item.label) failed: \(error.localizedDescription)"
        }
        await refresh()
    }
}
