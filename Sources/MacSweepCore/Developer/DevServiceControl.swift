import Darwin
import Foundation
import os

public enum DevServiceControl {
    private static let log = Logger(subsystem: Log.subsystem, category: "dev-services")

    /// Brew services plus dev-looking user launch agents that Homebrew doesn't manage.
    public static func list(home: String = NSHomeDirectory()) async -> (services: [DevService], error: String?) {
        var services: [DevService] = []
        var error: String?
        if let brew = Updater.brewPath {
            do {
                let result = try await DevShell.brew(brew, ["services", "list", "--json"], timeout: 60)
                services = DevServiceParser.parseBrewServices(result.stdout, currentUser: NSUserName())
                if result.status != 0 { error = DockerClient.firstLine(result.stderr) }
            } catch let failure {
                error = failure.localizedDescription
            }
        }
        let launchItems = await Task.detached(priority: .utility) { LaunchItemScanner.scan(home: home) }.value
        let state = await LaunchControl.readState()
        services += DevServiceParser.launchdServices(launchItems, statuses: state.statuses)
        return (services, error)
    }

    public static func perform(_ action: DevServiceAction, on service: DevService) async throws {
        guard service.isUserDomain else { throw DevCommandError.failed("\(service.name) runs as another user and needs sudo.") }
        log.info("\(action.rawValue, privacy: .public) \(service.name, privacy: .public)")
        switch service.source {
        case .homebrew:
            guard let brew = Updater.brewPath else { throw DevCommandError.notInstalled("Homebrew") }
            let result = try await DevShell.brew(brew, try DevServiceCommands.brew(action, name: service.name), timeout: 120)
            guard result.status == 0 else { throw DevCommandError.failed(DockerClient.firstLine(result.stderr)) }
        case .launchd:
            guard let plist = service.plistPath else { throw DevCommandError.failed("No launchd file for \(service.name).") }
            for arguments in try DevServiceCommands.launchctl(action, label: service.name, plistPath: plist, uid: getuid()) {
                let result = try await DevShell.run("/bin/launchctl", arguments, timeout: 30, tool: "launchctl")
                // bootstrap of an already-loaded job (5/37) and bootout of an unloaded one are not failures.
                guard result.status == 0 || arguments.first == "bootstrap" || arguments.first == "bootout" else {
                    throw DevCommandError.failed(DockerClient.firstLine(result.stderr))
                }
            }
        }
    }

    /// Log files declared in the service's plist, keeping only ones that exist.
    public static func logPaths(for service: DevService) -> [String] {
        guard let plist = service.plistPath, let data = FileManager.default.contents(atPath: plist) else { return [] }
        return DevServiceParser.logPaths(plist: data).filter { FileManager.default.fileExists(atPath: $0) }
    }
}
