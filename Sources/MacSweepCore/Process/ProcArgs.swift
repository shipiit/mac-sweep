import Darwin
import Foundation

/// Reads a process's argv via sysctl(KERN_PROCARGS2). Environment variables that follow argv
/// are deliberately never parsed so secrets in them are not surfaced.
public enum ProcArgs {
    public static func arguments(pid: Int32) -> [String]? {
        var argmaxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argmax: Int32 = 0
        var argmaxSize = MemoryLayout<Int32>.size
        guard sysctl(&argmaxMib, 2, &argmax, &argmaxSize, nil, 0) == 0, argmax > 0 else { return nil }

        // Most command lines (plus environment) fit in 64 KB; only grow to ARG_MAX (1 MB) when needed,
        // so scanning hundreds of processes doesn't churn hundreds of megabytes.
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        for capacity in [64 << 10, Int(argmax)] {
            var size = capacity
            var buffer = [UInt8](repeating: 0, count: size)
            if sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 {
                return parse(Array(buffer.prefix(size)))
            }
            guard errno == ENOMEM else { return nil }
        }
        return nil
    }

    /// Layout: int32 argc, exec path, NUL padding, then argc NUL-terminated strings.
    public static func parse(_ bytes: [UInt8]) -> [String]? {
        guard bytes.count >= 4 else { return nil }
        let argc = Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
        guard argc >= 0 else { return nil }
        var index = 4
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        while index < bytes.count, bytes[index] == 0 { index += 1 }

        var arguments: [String] = []
        while arguments.count < argc, index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            arguments.append(String(decoding: bytes[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
