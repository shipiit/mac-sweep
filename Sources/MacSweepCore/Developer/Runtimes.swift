import Foundation

public enum RuntimeLanguage: String, Sendable, CaseIterable, Identifiable {
    case node = "Node.js"
    case python = "Python"
    case ruby = "Ruby"

    public var id: String { rawValue }
}

/// A directory that holds one installed version per child folder.
public struct RuntimeSource: Sendable, Equatable {
    public let language: RuntimeLanguage
    public let manager: String
    public let directory: String

    public init(language: RuntimeLanguage, manager: String, directory: String) {
        self.language = language
        self.manager = manager
        self.directory = directory
    }
}

public struct RuntimeVersion: Sendable, Equatable, Identifiable {
    public let language: RuntimeLanguage
    public let manager: String
    public let version: String
    public let path: String
    public var size: UInt64?

    public var id: String { path }

    public init(language: RuntimeLanguage, manager: String, version: String, path: String, size: UInt64? = nil) {
        self.language = language
        self.manager = manager
        self.version = version
        self.path = path
        self.size = size
    }
}

public struct GlobalPackage: Sendable, Equatable, Identifiable {
    public let name: String
    public let version: String
    public let manager: String
    public let path: String

    public var id: String { manager + ":" + path }

    public init(name: String, version: String, manager: String, path: String) {
        self.name = name
        self.version = version
        self.manager = manager
        self.path = path
    }
}

public enum RuntimeInventory {
    public static func sources(home: String) -> [RuntimeSource] {
        [
            RuntimeSource(language: .node, manager: "nvm", directory: home + "/.nvm/versions/node"),
            RuntimeSource(language: .node, manager: "fnm", directory: home + "/.local/share/fnm/node-versions"),
            RuntimeSource(language: .node, manager: "fnm", directory: home + "/Library/Application Support/fnm/node-versions"),
            RuntimeSource(language: .node, manager: "volta", directory: home + "/.volta/tools/image/node"),
            RuntimeSource(language: .node, manager: "asdf", directory: home + "/.asdf/installs/nodejs"),
            RuntimeSource(language: .python, manager: "pyenv", directory: home + "/.pyenv/versions"),
            RuntimeSource(language: .python, manager: "uv", directory: home + "/.local/share/uv/python"),
            RuntimeSource(language: .python, manager: "asdf", directory: home + "/.asdf/installs/python"),
            RuntimeSource(language: .ruby, manager: "rbenv", directory: home + "/.rbenv/versions"),
            RuntimeSource(language: .ruby, manager: "asdf", directory: home + "/.asdf/installs/ruby"),
        ]
    }

    /// Lists version folders without measuring them; sizes are filled in later off the main thread.
    public static func versions(home: String, fileManager: FileManager = .default) -> [RuntimeVersion] {
        sources(home: home).flatMap { source -> [RuntimeVersion] in
            let names = (try? fileManager.contentsOfDirectory(atPath: source.directory)) ?? []
            return names.filter { isVersionFolder($0) }.compactMap { name in
                let path = source.directory + "/" + name
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
                return RuntimeVersion(language: source.language, manager: source.manager, version: displayVersion(name), path: path)
            }
            .sorted { compareVersions($0.version, $1.version) }
        }
    }

    /// Skips hidden entries and symlink aliases such as nvm's "default" or pyenv's "system".
    static func isVersionFolder(_ name: String) -> Bool {
        !name.hasPrefix(".") && name.contains(where: \.isNumber)
    }

    /// uv names folders like "cpython-3.12.4-macos-aarch64-none"; show "cpython 3.12.4".
    static func displayVersion(_ name: String) -> String {
        let parts = name.split(separator: "-")
        if parts.count >= 2, let first = parts.first, first.allSatisfy(\.isLetter), parts[1].first?.isNumber == true {
            return "\(first) \(parts[1])"
        }
        return name
    }

    /// Newest first, comparing dotted numeric parts so "v20.1" sorts above "v9.12".
    public static func compareVersions(_ lhs: String, _ rhs: String) -> Bool {
        func numbers(_ text: String) -> [Int] {
            text.split { !$0.isNumber }.compactMap { Int($0) }
        }
        let left = numbers(lhs)
        let right = numbers(rhs)
        if left == right { return lhs > rhs }
        return right.lexicographicallyPrecedes(left)
    }

    /// Folders that hold globally installed npm packages, one per Node install plus Homebrew's.
    public static func npmGlobalRoots(home: String, versions: [RuntimeVersion]) -> [String] {
        let fromVersions = versions.filter { $0.language == .node }.map { $0.path + "/lib/node_modules" }
        return ["/opt/homebrew/lib/node_modules", "/usr/local/lib/node_modules", home + "/.npm-global/lib/node_modules"] + fromVersions
    }

    public static func pnpmGlobalRoots(home: String, fileManager: FileManager = .default) -> [String] {
        let base = home + "/Library/pnpm/global"
        let stores = (try? fileManager.contentsOfDirectory(atPath: base)) ?? []
        return stores.filter { !$0.hasPrefix(".") }.sorted().map { base + "/" + $0 + "/node_modules" }
    }

    /// Reads `<root>/<pkg>/package.json` and `<root>/@scope/<pkg>/package.json`. npm itself is skipped (it ships with Node).
    public static func globalPackages(root: String, manager: String, fileManager: FileManager = .default) -> [GlobalPackage] {
        let names = (try? fileManager.contentsOfDirectory(atPath: root)) ?? []
        let folders = names.filter { !$0.hasPrefix(".") }.flatMap { name -> [String] in
            guard name.hasPrefix("@") else { return [name] }
            let scoped = (try? fileManager.contentsOfDirectory(atPath: root + "/" + name)) ?? []
            return scoped.filter { !$0.hasPrefix(".") }.map { name + "/" + $0 }
        }
        return folders.compactMap { folder in
            let path = root + "/" + folder
            guard let data = fileManager.contents(atPath: path + "/package.json"),
                  let info = parsePackageJSON(data), info.name != "npm", info.name != "corepack"
            else { return nil }
            return GlobalPackage(name: info.name, version: info.version, manager: manager, path: path)
        }
        .sorted { $0.name < $1.name }
    }

    public static func parsePackageJSON(_ data: Data) -> (name: String, version: String)? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = object["name"] as? String, !name.isEmpty
        else { return nil }
        return (name, object["version"] as? String ?? "")
    }

    public static func allGlobalPackages(home: String, versions: [RuntimeVersion]) -> [GlobalPackage] {
        let npm = npmGlobalRoots(home: home, versions: versions).flatMap { root in
            globalPackages(root: root, manager: npmManagerName(root: root, home: home))
        }
        let pnpm = pnpmGlobalRoots(home: home).flatMap { globalPackages(root: $0, manager: "pnpm") }
        return npm + pnpm
    }

    static func npmManagerName(root: String, home: String) -> String {
        if root.hasPrefix("/opt/homebrew") || root.hasPrefix("/usr/local") { return "npm (system)" }
        let version = ((root as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        return "npm (\((version as NSString).lastPathComponent))"
    }
}
