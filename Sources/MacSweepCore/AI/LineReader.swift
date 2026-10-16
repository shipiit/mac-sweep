import Foundation

/// Streams a file line by line in 4 MB chunks, so multi-gigabyte transcripts never load into memory.
/// `filter` is checked on raw bytes first, so lines without usage data are never decoded.
enum LineReader {
    /// Returns the offset just past the last complete line, so a later call can continue from there.
    /// A trailing line without a newline is still passed to `body` but not counted as consumed.
    @discardableResult
    static func forEachLine(path: String, from offset: UInt64 = 0, containing filter: [UInt8], _ body: (Data) -> Void) -> UInt64 {
        guard let handle = FileHandle(forReadingAtPath: path) else { return offset }
        defer { try? handle.close() }
        if offset > 0 {
            do { try handle.seek(toOffset: offset) } catch { return offset }
        }
        var consumed = offset
        var carry = Data()
        let newline = UInt8(ascii: "\n")
        let needle = Data(filter)
        while true {
            // Each chunk and each line's JSON objects are released immediately; without the pools,
            // Foundation objects from millions of lines pile up until the whole scan finishes (GBs).
            let more: Bool = autoreleasepool {
                guard let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty else { return false }
                var buffer = carry
                buffer.append(chunk)
                var start = buffer.startIndex
                while let end = buffer[start...].firstIndex(of: newline) {
                    let line = buffer[start..<end]
                    if needle.isEmpty || line.range(of: needle) != nil {
                        autoreleasepool { body(Data(line)) }
                    }
                    start = buffer.index(after: end)
                }
                consumed += UInt64(buffer.distance(from: buffer.startIndex, to: start))
                carry = Data(buffer[start...])
                return true
            }
            if !more { break }
        }
        if !carry.isEmpty, needle.isEmpty || carry.range(of: needle) != nil { autoreleasepool { body(carry) } }
        return consumed
    }
}
