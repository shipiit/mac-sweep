import Foundation
import MacSweepCore
import Observation

@MainActor
@Observable
final class MaintenanceModel {
    enum Status: Equatable {
        case idle
        case running
        case done(Date)
        case failed(String)
    }

    private(set) var status: [MaintenanceTask: Status] = [:]

    func status(of task: MaintenanceTask) -> Status { status[task] ?? .idle }

    func run(_ task: MaintenanceTask) async {
        status[task] = .running
        do {
            _ = try await task.run()
            status[task] = .done(Date())
        } catch AdminRunner.AdminError.cancelled {
            status[task] = .idle
        } catch {
            status[task] = .failed(error.localizedDescription)
        }
    }
}
