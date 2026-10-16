import Foundation

public struct ProcessTraffic: Sendable, Equatable {
    public let pid: Int32
    public let name: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(pid: Int32, name: String, bytesIn: UInt64, bytesOut: UInt64) {
        self.pid = pid
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// Parses `nettop -L 1 -P -x -n -J bytes_in,bytes_out`: CSV rows of `name.pid,bytes_in,bytes_out,`.
/// Counts are cumulative per process (since it started), so the UI labels them that way.
public enum NettopParser {
    public static let arguments = ["-L", "1", "-P", "-x", "-n", "-J", "bytes_in,bytes_out"]

    public static func parse(_ output: String) -> [Int32: ProcessTraffic] {
        var result: [Int32: ProcessTraffic] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            var fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if fields.last == "" { fields.removeLast() }
            // Take the last two fields as counters so a comma inside a process name can't shift them.
            guard fields.count >= 3, let bytesOut = UInt64(fields[fields.count - 1]), let bytesIn = UInt64(fields[fields.count - 2])
            else { continue }
            let label = fields.dropLast(2).joined(separator: ",")
            guard let dot = label.lastIndex(of: "."), let pid = Int32(label[label.index(after: dot)...]), pid > 0 else { continue }
            let name = String(label[..<dot])
            if let existing = result[pid] {
                result[pid] = ProcessTraffic(pid: pid, name: name, bytesIn: existing.bytesIn &+ bytesIn, bytesOut: existing.bytesOut &+ bytesOut)
            } else {
                result[pid] = ProcessTraffic(pid: pid, name: name, bytesIn: bytesIn, bytesOut: bytesOut)
            }
        }
        return result
    }
}
