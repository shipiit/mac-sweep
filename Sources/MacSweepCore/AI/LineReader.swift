import Foundation

/// Streams a file line by line in 4 MB chunks, so multi-gigabyte transcripts never load into memory.
/// `filter` is checked on raw bytes first, so lines without usage data are never decoded.
enum LineReader {
    static func forEachLine(path: String, containing filter: [UInt8], _ body: (Data) -> Void) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
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
                carry = Data(buffer[start...])
                return true
            }
            if !more { break }
        }
        if !carry.isEmpty, needle.isEmpty || carry.range(of: needle) != nil { autoreleasepool { body(carry) } }
    }
}
