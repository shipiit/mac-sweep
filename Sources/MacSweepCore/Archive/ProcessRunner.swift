import Foundation

/// Runs a tool with explicit arguments (no shell) and terminates it if the calling task is cancelled,
/// so a cancelled multi-gigabyte `ditto` doesn't keep running in the background.
enum ProcessRunner {
    static func run(_ executable: String, _ arguments: [String]) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        let box = ProcessBox(process)
        // Drained as it arrives so a chatty failure can't fill the pipe and stall the tool.
        let collected = LockedBox(Data())
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            collected.set(collected.get() + chunk)
        }
        let result: ShellResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    errors.fileHandleForReading.readabilityHandler = nil
                    let rest = errors.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(decoding: collected.get() + rest, as: UTF8.self)
                    continuation.resume(returning: ShellResult(status: finished.terminationStatus, stdout: "", stderr: stderr))
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    errors.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: ShellError.launchFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            box.terminate()
        }
        try Task.checkCancellation()
        return result
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) { self.process = process }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}
