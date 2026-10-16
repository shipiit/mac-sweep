import Foundation

/// Renders a selection as a shell script the user can review and run themselves.
public enum CleanupScript {
    public static func make(_ targets: [CleanupTarget], home: String, generatedAt: Date = Date()) -> String {
        let allowed = targets.filter { PathGuard.canRemove($0.path, home: home) }
        let total = allowed.reduce(UInt64(0)) { $0 + $1.size }
        let size = ByteCountFormatter.string(fromByteCount: Int64(clamping: total), countStyle: .file)
        var lines = [
            "#!/bin/bash",
            "# MacSweep cleanup script: \(allowed.count) locations, \(size)",
            "# Generated \(ISO8601DateFormatter().string(from: generatedAt)). Review before running.",
            "set -euo pipefail",
            "",
        ]
        for target in allowed.sorted(by: { $0.size > $1.size }) {
            let label = ByteCountFormatter.string(fromByteCount: Int64(clamping: target.size), countStyle: .file)
            lines.append("rm -rf -- \(quote(target.path))  # \(label)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// POSIX single-quote escaping: close, escaped quote, reopen.
    static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
