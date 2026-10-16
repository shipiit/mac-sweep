import Foundation
import os

public enum DockerStatus: Sendable, Equatable {
    case notInstalled
    case notRunning
    case failed(String)
    case ready(DockerUsage)
}

public enum DockerPrune: String, Sendable, CaseIterable, Identifiable {
    case danglingImages = "Dangling images"
    case buildCache = "Build cache"

    public var id: String { rawValue }

    public var arguments: [String] {
        switch self {
        case .danglingImages: ["image", "prune", "--force"]
        case .buildCache: ["builder", "prune", "--force"]
        }
    }
}

public enum DockerClient {
    private static let log = Logger(subsystem: Log.subsystem, category: "docker")

    public static func executableCandidates(home: String) -> [String] {
        [
            "/usr/local/bin/docker", "/opt/homebrew/bin/docker", home + "/.orbstack/bin/docker", home + "/.rd/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker", "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
        ]
    }

    public static func socketCandidates(home: String) -> [String] {
        [
            home + "/.docker/run/docker.sock", "/var/run/docker.sock", home + "/.orbstack/run/docker.sock",
            home + "/.colima/default/docker.sock", home + "/.colima/docker.sock", home + "/.rd/docker.sock",
        ]
    }

    /// A socket file existing doesn't prove the daemon answers, but its absence proves it doesn't,
    /// which spares spawning a CLI that might hang waiting for one.
    public static func hasSocket(home: String, exists: (String) -> Bool = FileManager.default.fileExists) -> Bool {
        socketCandidates(home: home).contains(where: exists)
    }

    public static func status(home: String = NSHomeDirectory()) async -> DockerStatus {
        guard let docker = ToolLocator.first(executableCandidates(home: home)) else { return .notInstalled }
        guard hasSocket(home: home) else { return .notRunning }
        do {
            let summary = try await DevShell.run(docker, ["system", "df", "--format", "json"], timeout: 30, tool: "Docker")
            guard summary.status == 0 else {
                return DockerParser.isDaemonDown(summary.stderr) ? .notRunning : .failed(firstLine(summary.stderr))
            }
            var usage = DockerUsage(rows: DockerParser.parseSummary(summary.stdout))
            if let verbose = try? await DevShell.run(docker, ["system", "df", "-v", "--format", "json"], timeout: 60, tool: "Docker"),
               verbose.status == 0 {
                let detail = DockerParser.parseVerbose(verbose.stdout)
                usage.images = detail.images
                usage.containers = detail.containers
                usage.volumes = detail.volumes
            }
            return .ready(usage)
        } catch {
            log.error("docker df failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    public static func prune(_ kind: DockerPrune, home: String = NSHomeDirectory()) async throws -> UInt64 {
        guard let docker = ToolLocator.first(executableCandidates(home: home)) else { throw DevCommandError.notInstalled("Docker") }
        log.info("pruning \(kind.rawValue, privacy: .public)")
        let result = try await DevShell.run(docker, kind.arguments, timeout: 600, tool: "Docker")
        guard result.status == 0 else { throw DevCommandError.failed(firstLine(result.stderr)) }
        return parseReclaimed(result.stdout)
    }

    /// Reads the "Total reclaimed space: 1.2GB" footer printed by `docker … prune`.
    public static func parseReclaimed(_ output: String) -> UInt64 {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased().contains("reclaimed space") else { continue }
            return HumanSize.parse(String(parts[1])) ?? 0
        }
        return 0
    }

    static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }
}
