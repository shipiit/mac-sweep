import Foundation

public enum LaunchScope: String, Sendable, CaseIterable {
    case userAgent = "Your agents"
    case globalAgent = "All-user agents"
    case daemon = "System daemons"

    public var requiresAdmin: Bool { self == .daemon }
}

public struct LaunchItem: Identifiable, Hashable, Sendable {
    public let label: String
    public let plistPath: String
    public let scope: LaunchScope
    public let program: String?
    public let arguments: [String]
    public let runAtLoad: Bool
    public let keepAlive: Bool
    public let disabledInPlist: Bool
    public let startInterval: Int?

    public var id: String { plistPath }

    public var executable: String? { program ?? arguments.first }

    public init(label: String, plistPath: String, scope: LaunchScope, program: String?, arguments: [String],
                runAtLoad: Bool, keepAlive: Bool, disabledInPlist: Bool, startInterval: Int?) {
        self.label = label
        self.plistPath = plistPath
        self.scope = scope
        self.program = program
        self.arguments = arguments
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.disabledInPlist = disabledInPlist
        self.startInterval = startInterval
    }
}

public struct LaunchStatus: Sendable, Equatable {
    public let pid: Int32?
    public let lastExitStatus: Int32?
}

public enum LaunchItemScanner {
    public static func directories(home: String) -> [(String, LaunchScope)] {
        [
            (home + "/Library/LaunchAgents", .userAgent),
            ("/Library/LaunchAgents", .globalAgent),
            ("/Library/LaunchDaemons", .daemon),
        ]
    }

    public static func scan(home: String = NSHomeDirectory()) -> [LaunchItem] {
        directories(home: home).flatMap { directory, scope -> [LaunchItem] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            return names.filter { $0.hasSuffix(".plist") }.compactMap { name -> LaunchItem? in
                let path = directory + "/" + name
                guard let data = FileManager.default.contents(atPath: path) else { return nil }
                return parse(data, path: path, scope: scope)
            }
        }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    public static func parse(_ data: Data, path: String, scope: LaunchScope) -> LaunchItem? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any]
        else { return nil }
        let label = dictionary["Label"] as? String ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let keepAlive: Bool
        switch dictionary["KeepAlive"] {
        case let flag as Bool: keepAlive = flag
        case is [String: Any]: keepAlive = true
        default: keepAlive = false
        }
        return LaunchItem(
            label: label,
            plistPath: path,
            scope: scope,
            program: dictionary["Program"] as? String,
            arguments: dictionary["ProgramArguments"] as? [String] ?? [],
            runAtLoad: dictionary["RunAtLoad"] as? Bool ?? false,
            keepAlive: keepAlive,
            disabledInPlist: dictionary["Disabled"] as? Bool ?? false,
            startInterval: dictionary["StartInterval"] as? Int
        )
    }
}

public enum LaunchctlParser {
    /// Parses `launchctl list`: `PID\tStatus\tLabel`, with `-` for no PID.
    public static func parseList(_ output: String) -> [String: LaunchStatus] {
        var result: [String: LaunchStatus] = [:]
        for line in output.split(whereSeparator: \.isNewline).dropFirst() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let label = fields[2...].joined(separator: "\t")
            result[label] = LaunchStatus(pid: Int32(fields[0]), lastExitStatus: Int32(fields[1]))
        }
        return result
    }

    /// Parses `launchctl print-disabled`: lines like `"com.foo" => disabled` (or `=> true` on older macOS).
    public static func parseDisabled(_ output: String) -> Set<String> {
        var disabled = Set<String>()
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let state = parts[1].trimmingCharacters(in: .whitespaces)
            guard state == "disabled" || state == "true" else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !label.isEmpty { disabled.insert(label) }
        }
        return disabled
    }
}
