import CoreServices
import Foundation

/// Recursive FSEvents watcher with coalescing latency; calls `onChange` on the main queue.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init?(paths: [String], latency: TimeInterval = 1.5, onChange: @escaping () -> Void) {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return nil }
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, existing as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               latency, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
