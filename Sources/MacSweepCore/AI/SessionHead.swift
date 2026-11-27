import Foundation

/// What a transcript says about itself near its start: the title Claude gave it and the folder it ran in.
public struct SessionHead: Sendable, Equatable {
    public var title: String?
    public var workingDirectory: String?

    /// Reads only the first part of the file, so multi-gigabyte transcripts stay cheap.
    public static func read(_ path: String, limit: Int = 512 << 10) -> SessionHead {
        guard let handle = FileHandle(forReadingAtPath: path) else { return SessionHead() }
        defer { try? handle.close() }
        return parse((try? handle.read(upToCount: limit)) ?? Data())
    }

    static func parse(_ data: Data) -> SessionHead {
        var head = SessionHead()
        var firstPrompt: String?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard head.title == nil || head.workingDirectory == nil,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if head.title == nil, let title = object["aiTitle"] as? String ?? object["summary"] as? String { head.title = clean(title) }
            if head.workingDirectory == nil, let directory = object["cwd"] as? String, !directory.isEmpty { head.workingDirectory = directory }
            if firstPrompt == nil, object["type"] as? String == "user", object["isMeta"] as? Bool != true,
               let text = (object["message"] as? [String: Any])?["content"] as? String, !text.hasPrefix("<") {
                firstPrompt = clean(text)
            }
        }
        if head.title == nil { head.title = firstPrompt }
        return head
    }

    static func clean(_ text: String) -> String? {
        let oneLine = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !oneLine.isEmpty else { return nil }
        return oneLine.count > 90 ? String(oneLine.prefix(90)) + "…" : oneLine
    }
}
