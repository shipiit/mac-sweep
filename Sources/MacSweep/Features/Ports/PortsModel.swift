import Foundation
import MacSweepCore
import Observation

@MainActor
@Observable
final class PortsModel {
    private(set) var ports: [ListeningPort] = []
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var error: String?
    /// True once the user has authorised an admin scan, which includes other users' and root's sockets.
    private(set) var includesSystem = false
    var includeUDP = false
    /// Where each listening process runs from and what started it, keyed by PID.
    private(set) var details: [Int32: PortProcessDetails] = [:]

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            ports = includesSystem
                ? try await PortScanner.scanAsAdmin(includeUDP: includeUDP)
                : try await PortScanner.scan(includeUDP: includeUDP)
            error = nil
            lastUpdated = Date()
            let pids = Set(ports.map(\.pid))
            details = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: pids.map { pid in
                    (pid, PortProcessDetails(executable: ProcReader.executablePath(pid), workingDirectory: ProcReader.workingDirectory(pid),
                                             arguments: ProcArgs.arguments(pid: pid) ?? []))
                })
            }.value
        } catch AdminRunner.AdminError.cancelled {
            includesSystem = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setIncludesSystem(_ value: Bool) async {
        includesSystem = value
        await refresh()
    }
}

struct PortProcessDetails: Sendable, Equatable {
    let executable: String?
    let workingDirectory: String?
    let arguments: [String]

    var summary: String? { PortDescriber.summary(arguments) }

    /// The project folder, unless the process just runs from / or the home folder.
    var location: String? {
        guard let cwd = workingDirectory, cwd != "/", cwd != NSHomeDirectory() else { return nil }
        return cwd
    }
}
