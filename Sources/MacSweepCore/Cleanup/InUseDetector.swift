import Foundation

public struct RunningProcessInfo: Sendable, Equatable {
    public let pid: Int32
    public let name: String
    public let executable: String?
    public let workingDirectory: String?
    /// Command-line arguments; interpreters (node, python) run scripts whose paths only appear here.
    public let arguments: [String]

    public init(pid: Int32, name: String, executable: String?, workingDirectory: String?, arguments: [String] = []) {
        self.pid = pid
        self.name = name
        self.executable = executable
        self.workingDirectory = workingDirectory
        self.arguments = arguments
    }
}

public struct RunningAppInfo: Sendable, Equatable {
    public let name: String
    public let bundleID: String?

    public init(name: String, bundleID: String?) {
        self.name = name
        self.bundleID = bundleID
    }
}

public struct InUseConflict: Sendable, Equatable, Identifiable {
    public let targetPath: String
    public let owner: String
    public let reason: String

    public var id: String { targetPath + "|" + owner }
}

/// Finds selected cleanup targets that something running right now depends on, so they can be
/// skipped instead of pulled out from under a live process.
public enum InUseDetector {
    public static func conflicts(
        targets: [String], processes: [RunningProcessInfo], apps: [RunningAppInfo], home: String
    ) -> [InUseConflict] {
        var found: [InUseConflict] = []
        for target in targets {
            if let process = processes.first(where: { contains(target, $0.executable) }) {
                found.append(InUseConflict(targetPath: target, owner: process.name, reason: "\(process.name) (PID \(process.pid)) is running from inside it"))
                continue
            }
            if let process = processes.first(where: { process in process.arguments.contains { contains(target, $0) } }) {
                found.append(InUseConflict(targetPath: target, owner: process.name,
                                           reason: "\(process.name) (PID \(process.pid)) is running a script from inside it"))
                continue
            }
            if let process = processes.first(where: { contains(target, $0.workingDirectory) }) {
                found.append(InUseConflict(targetPath: target, owner: process.name, reason: "\(process.name) (PID \(process.pid)) is working in this folder"))
                continue
            }
            // Build output (.next, node_modules…) while a dev server or shell sits in that project.
            let project = (target as NSString).deletingLastPathComponent
            if project != home, let process = processes.first(where: { $0.workingDirectory == project }) {
                found.append(InUseConflict(targetPath: target, owner: process.name,
                                           reason: "\(process.name) (PID \(process.pid)) is running in this project"))
                continue
            }
            if let hint = ownerHint(for: target, home: home), let app = apps.first(where: { matches($0, hint: hint) }) {
                found.append(InUseConflict(targetPath: target, owner: app.name, reason: "\(app.name) is open and uses this cache. Quit it first"))
            }
        }
        return found
    }

    /// The app a per-app folder belongs to: `~/Library/{Caches,Application Support,Containers}/<owner>/…`.
    public static func ownerHint(for path: String, home: String) -> String? {
        let roots = ["/Library/Caches/", "/Library/Application Support/", "/Library/Containers/", "/Library/HTTPStorages/"]
        for root in roots {
            let prefix = home + root
            guard path.hasPrefix(prefix) else { continue }
            let owner = path.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
            return owner.flatMap { $0.count >= 4 ? $0 : nil }
        }
        return nil
    }

    static func matches(_ app: RunningAppInfo, hint: String) -> Bool {
        let needle = hint.lowercased()
        if let bundle = app.bundleID?.lowercased(), bundle == needle || bundle.hasSuffix("." + needle) { return true }
        // "Code" → "Visual Studio Code", "Slack" → "Slack", "com.google.Chrome" → bundle match above.
        let words = app.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return words.contains { $0 == needle } || app.name.lowercased() == needle
    }

    private static func contains(_ target: String, _ path: String?) -> Bool {
        guard let path else { return false }
        return path == target || PathTools.isDescendant(path, of: target)
    }
}
