import Foundation

public struct LoginItem: Identifiable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let hidden: Bool

    public var id: String { path.isEmpty ? name : path }
}

public struct BackgroundItem: Identifiable, Sendable, Equatable {
    public let name: String
    public let developer: String?
    public let type: String
    public let enabled: Bool
    public let identifier: String?
    public let url: String?

    public var id: String { (identifier ?? name) + (url ?? "") }
}

/// "Open at Login" apps (via System Events) and the full Background Task Management list (via sfltool, admin).
public enum LoginItems {
    static let listScript = """
    set out to ""
    tell application "System Events"
        repeat with i in every login item
            set out to out & (name of i) & tab & (path of i) & tab & ((hidden of i) as string) & linefeed
        end repeat
    end tell
    return out
    """

    public static func list() async throws -> [LoginItem] {
        let result = try await Shell.run("/usr/bin/osascript", ["-e", listScript])
        guard result.status == 0 else { throw AdminRunner.AdminError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return parseList(result.stdout)
    }

    public static func remove(_ item: LoginItem) async throws {
        try await run("tell application \"System Events\" to delete login item \"\(escape(item.name))\"")
    }

    public static func add(appPath: String) async throws {
        try await run("tell application \"System Events\" to make login item at end with properties {path:\"\(escape(appPath))\", hidden:false}")
    }

    public static func backgroundItems() async throws -> [BackgroundItem] {
        parseDump(try await AdminRunner.runFixed("/usr/bin/sfltool dumpbtm"))
    }

    public static func parseList(_ output: String) -> [LoginItem] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2, !fields[0].isEmpty else { return nil }
            return LoginItem(name: fields[0], path: fields[1], hidden: fields.count > 2 && fields[2] == "true")
        }
    }

    /// Parses `sfltool dumpbtm` records ("Name: …", "Type: app (0x2)", "Disposition: [enabled, allowed, …]").
    public static func parseDump(_ output: String) -> [BackgroundItem] {
        var items: [BackgroundItem] = []
        var fields: [String: String] = [:]
        func flush() {
            if let name = fields["Name"], let type = fields["Type"] {
                let disposition = fields["Disposition"] ?? ""
                items.append(BackgroundItem(
                    name: name, developer: fields["Developer Name"].flatMap { $0 == "(null)" ? nil : $0 },
                    type: type.components(separatedBy: " (").first ?? type,
                    enabled: disposition.contains("enabled") && !disposition.contains("disabled"),
                    identifier: fields["Identifier"], url: fields["URL"].flatMap { $0 == "(null)" ? nil : $0 }
                ))
            }
            fields = [:]
        }
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#"), line.hasSuffix(":") { flush(); continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if fields[key] == nil { fields[key] = value }
        }
        flush()
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func run(_ script: String) async throws {
        let result = try await Shell.run("/usr/bin/osascript", ["-e", script])
        if result.status != 0 { throw AdminRunner.AdminError.failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
