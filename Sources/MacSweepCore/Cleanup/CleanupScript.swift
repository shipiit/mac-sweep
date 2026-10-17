import Foundation

/// Renders a selection as a shell script the user can review and run themselves.
public enum CleanupScript {
    /// Tool-managed caches use the tool's own command (once per command, skipped if the tool isn't installed);
    /// everything else is `rm -rf`. Paths in `reviewFirst` are written commented out so nothing risky runs by default.
    public static func make(_ targets: [CleanupTarget], home: String, reviewFirst: Set<String> = [], generatedAt: Date = Date()) -> String {
        let allowed = targets.filter { PathGuard.canRemove($0.path, home: home) }
        let total = allowed.reduce(UInt64(0)) { $0 + $1.size }
        var lines = [
            "#!/bin/bash",
            "# MacSweep cleanup script: \(allowed.count) locations, \(label(total))",
            "# Generated \(ISO8601DateFormatter().string(from: generatedAt)). Review before running; nothing has been deleted.",
            "# Lines starting with '# REVIEW' are for things you should check first; remove the '# ' to run them.",
            "set -uo pipefail",
            "",
        ]
        var emitted = Set<String>()
        for target in allowed.sorted(by: { $0.size > $1.size }) {
            let isReview = reviewFirst.contains(target.path)
            let prefix = isReview ? "# REVIEW " : ""
            if let tool = ToolCleanCommands.command(for: target.path, home: home) {
                guard emitted.insert(tool.command).inserted else { continue }
                lines.append("\(prefix)command -v \(tool.tool) >/dev/null && \(tool.command)  # \(Format.home(target.path, home)) · \(label(target.size))")
            } else {
                lines.append("\(prefix)rm -rf -- \(quote(target.path))  # \(label(target.size))")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func label(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    /// POSIX single-quote escaping: close, escaped quote, reopen.
    static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private enum Format {
    static func home(_ path: String, _ home: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
