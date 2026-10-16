import CryptoKit
import Darwin
import Foundation

public enum FileHashError: Error, Equatable {
    case unreadable(String)
}

/// Streaming SHA-256 with bounded memory: never more than one chunk of a file is held at once.
enum FileHasher {
    static let headLength = 64 * 1024
    static let chunkLength = 1 << 20

    /// Hash of the first 64 KB; for files no larger than that it is the hash of the whole file.
    static func headHash(_ path: String) throws -> String {
        try hash(path, limit: headLength, onBytes: nil)
    }

    static func fullHash(_ path: String, onBytes: ((Int) -> Void)? = nil) throws -> String {
        try hash(path, limit: nil, onBytes: onBytes)
    }

    private static func hash(_ path: String, limit: Int?, onBytes: ((Int) -> Void)?) throws -> String {
        // O_NOFOLLOW: a file swapped for a symlink after the walk is refused rather than followed.
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw FileHashError.unreadable(path) }
        // Large sequential reads would otherwise evict everything else from the page cache.
        if limit == nil { _ = fcntl(descriptor, F_NOCACHE, 1) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            try Task.checkCancellation()
            let wanted = min(chunkLength, remaining)
            let chunk: Data? = try autoreleasepool {
                do {
                    return try handle.read(upToCount: wanted)
                } catch {
                    throw FileHashError.unreadable(path)
                }
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
            onBytes?(chunk.count)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Runs `transform` over `items` with at most `limit` in flight, adding work only as slots free up,
/// so a 100k-file job never allocates 100k tasks. Result order is not preserved.
enum Concurrent {
    static func map<Item: Sendable, Output: Sendable>(
        _ items: [Item], limit: Int, _ transform: @escaping @Sendable (Item) async -> Output
    ) async -> [Output] {
        await withTaskGroup(of: Output.self) { group in
            var index = 0
            while index < min(max(limit, 1), items.count) {
                let item = items[index]
                group.addTask { await transform(item) }
                index += 1
            }
            var results: [Output] = []
            results.reserveCapacity(items.count)
            while let output = await group.next() {
                results.append(output)
                guard index < items.count, !Task.isCancelled else { continue }
                let item = items[index]
                group.addTask { await transform(item) }
                index += 1
            }
            return results
        }
    }
}

/// Thread-safe progress for the duplicate, photo and archive finders, polled by the UI.
public final class FinderProgress: @unchecked Sendable {
    public enum Phase: String, Sendable {
        case listing = "Listing files"
        case comparingStarts = "Comparing file starts"
        case hashing = "Comparing full contents"
        case analyzing = "Analyzing images"
        case grouping = "Grouping"
        case measuring = "Measuring folders"
    }

    public struct Snapshot: Sendable, Equatable {
        public var phase: Phase = .listing
        public var filesSeen = 0
        public var done = 0
        public var total = 0
        public var bytes: UInt64 = 0

        public var fraction: Double? { total > 0 ? min(Double(done) / Double(total), 1) : nil }
    }

    private let lock = NSLock()
    private var value = Snapshot()

    public init() {}

    public func snapshot() -> Snapshot { lock.withLock { value } }

    func begin(_ phase: Phase, total: Int) {
        lock.withLock {
            value.phase = phase
            value.total = total
            value.done = 0
        }
    }

    func seen(_ count: Int) { lock.withLock { value.filesSeen = count } }
    func step() { lock.withLock { value.done += 1 } }
    func add(bytes: Int) { lock.withLock { value.bytes += UInt64(max(bytes, 0)) } }
}
