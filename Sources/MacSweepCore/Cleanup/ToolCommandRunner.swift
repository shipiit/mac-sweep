import Foundation

extension ToolCleanCommands {
    /// The distinct tool commands for the given targets, leaving out review-first ones, in first-seen order.
    public static func plan(_ targets: [CleanupTarget], home: String, reviewFirst: Set<String>) -> [Command] {
        var seen = Set<String>()
        return targets.sorted { $0.size > $1.size }.compactMap { target -> Command? in
            guard !reviewFirst.contains(target.path), let command = command(for: target.path, home: home),
                  seen.insert(command.command).inserted else { return nil }
            return command
        }
    }
}

/// Runs one fixed tool command (from `ToolCleanCommands`) in a login shell and streams its output.
/// Only commands from MacSweep's own table are run; nothing typed by a user is ever executed.
public enum ToolCommandRunner {
    public enum Outcome: Equatable, Sendable {
        case finished(status: Int32)
        case toolMissing
        case timedOut
    }

    /// Folders where developer tools usually live, added to PATH because GUI apps don't inherit the shell's.
    static func searchPath(home: String) -> String {
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.cargo/bin", home + "/go/bin", home + "/.bun/bin"]
        let nvm = home + "/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm),
           let newest = versions.sorted(by: { VersionedFolders.isNewer($0.trimmingCharacters(in: ["v"]), than: $1.trimmingCharacters(in: ["v"])) }).first {
            dirs.insert(nvm + "/" + newest + "/bin", at: 0)
        }
        return (dirs + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
    }

    public static func run(_ command: ToolCleanCommands.Command, home: String = NSHomeDirectory(), timeout: TimeInterval = 600,
                           onLine: @escaping @Sendable (String) -> Void) async -> Outcome {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let script = "command -v \(command.tool) >/dev/null 2>&1 || exit 127\n\(command.command)"
            process.arguments = ["-c", script]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = searchPath(home: home)
            environment["CI"] = "1"
            process.environment = environment
            process.currentDirectoryURL = URL(fileURLWithPath: home)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            let buffer = LineBuffer(onLine: onLine)
            pipe.fileHandleForReading.readabilityHandler = { handle in buffer.feed(handle.availableData) }
            let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            process.terminationHandler = { finished in
                timer.cancel()
                pipe.fileHandleForReading.readabilityHandler = nil
                buffer.feed(pipe.fileHandleForReading.readDataToEndOfFile())
                buffer.flush()
                if finished.terminationReason == .uncaughtSignal { continuation.resume(returning: .timedOut) }
                else if finished.terminationStatus == 127 { continuation.resume(returning: .toolMissing) }
                else { continuation.resume(returning: .finished(status: finished.terminationStatus)) }
            }
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            } catch {
                continuation.resume(returning: .toolMissing)
            }
        }
    }
}

/// Splits streamed bytes into lines for the live log.
final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        let lines: [String] = lock.withLock {
            pending.append(data)
            var out: [String] = []
            while let index = pending.firstIndex(of: UInt8(ascii: "\n")) {
                out.append(String(decoding: pending[pending.startIndex..<index], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...index)
            }
            return out
        }
        lines.filter { !$0.isEmpty }.forEach(onLine)
    }

    func flush() {
        let rest: String = lock.withLock {
            defer { pending.removeAll() }
            return String(decoding: pending, as: UTF8.self)
        }
        if !rest.isEmpty { onLine(rest) }
    }
}
