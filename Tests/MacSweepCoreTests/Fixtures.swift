import Foundation
@testable import MacSweepCore

enum Fixtures {
    static let home = "/Users/test"

    static func dir(_ path: String, size: UInt64 = 0, modified: Date? = nil, _ children: [FileNode] = []) -> FileNode {
        let total = children.isEmpty ? size : children.reduce(0) { $0 + $1.size }
        return FileNode(
            path: path, name: (path as NSString).lastPathComponent, kind: .directory, size: total,
            itemCount: max(children.reduce(0) { $0 + $1.itemCount }, 1), modified: modified,
            children: children.sorted { $0.size > $1.size }
        )
    }

    static func file(_ path: String, size: UInt64, modified: Date? = nil) -> FileNode {
        FileNode(path: path, name: (path as NSString).lastPathComponent, kind: .file, size: size, modified: modified)
    }

    /// Creates a fresh temporary directory and returns its resolved path.
    static func makeTempDir() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macsweep-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath().path
    }

    static func write(_ path: String, bytes: Int) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: bytes).write(to: URL(fileURLWithPath: path))
    }
}
