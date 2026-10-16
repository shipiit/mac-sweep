import MacSweepCore
import SwiftUI

enum DevTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case docker = "Docker"
    case homebrew = "Homebrew"
    case runtimes = "Runtimes"
    case xcode = "Xcode"
    case nodeModules = "node_modules"
    case services = "Services"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .docker: "shippingbox"
        case .homebrew: "mug"
        case .runtimes: "chevron.left.forwardslash.chevron.right"
        case .xcode: "hammer"
        case .nodeModules: "folder.badge.gearshape"
        case .services: "server.rack"
        }
    }
}

/// Everything that removes data or changes a running system goes through one confirmation.
enum DevPendingAction: Equatable {
    case dockerPrune(DockerPrune, estimate: UInt64)
    case brewCleanup(estimate: UInt64)
    case deleteUnavailableSimulators(count: Int)
    case trash(paths: [String], title: String, size: UInt64)

    var title: String {
        switch self {
        case .dockerPrune(let kind, _): "Remove Docker \(kind.rawValue.lowercased())?"
        case .brewCleanup: "Run brew cleanup?"
        case .deleteUnavailableSimulators(let count): "Delete \(count) unavailable simulator\(count == 1 ? "" : "s")?"
        case .trash(_, let title, _): "Move \(title) to the Trash?"
        }
    }

    var message: String {
        switch self {
        case .dockerPrune(.danglingImages, let estimate):
            "Untagged images no container uses will be deleted (about \(Format.bytes(estimate))). This can't be undone; images can be pulled or rebuilt again."
        case .dockerPrune(.buildCache, let estimate):
            "Docker's build cache will be cleared (about \(Format.bytes(estimate))). The next builds will be slower while it refills."
        case .brewCleanup(let estimate):
            "Homebrew removes old versions and cached downloads (about \(Format.bytes(estimate))). Installed tools keep working."
        case .deleteUnavailableSimulators:
            "Simulators for runtimes that are no longer installed will be deleted with simctl, along with their data."
        case .trash(let paths, _, let size):
            "\(paths.count) item\(paths.count == 1 ? "" : "s") (\(Format.bytes(size))) go to the Trash, so you can put them back until it's emptied."
        }
    }

    var buttonTitle: String {
        switch self {
        case .trash: "Move to Trash"
        case .brewCleanup: "Clean Up"
        default: "Delete"
        }
    }
}

struct DevConfirmation: Identifiable {
    let id = UUID()
    let action: DevPendingAction
}

/// What the overview needs to know about a section that may not have loaded yet.
enum DevSectionState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool { self == .loading }
}
