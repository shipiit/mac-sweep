import Foundation

/// The tool's own clean command for caches a tool manages, so a script cleans them the supported way
/// (keeping indexes and lock files consistent) instead of deleting folders behind the tool's back.
public enum ToolCleanCommands {
    public struct Command: Equatable, Sendable {
        public let tool: String
        public let command: String
    }

    /// Home-relative prefixes → command. The first match wins, so more specific prefixes come first.
    static let table: [(prefix: String, command: Command)] = [
        ("/.npm", Command(tool: "npm", command: "npm cache clean --force")),
        ("/Library/pnpm/store", Command(tool: "pnpm", command: "pnpm store prune")),
        ("/Library/Caches/Yarn", Command(tool: "yarn", command: "yarn cache clean")),
        ("/.bun/install/cache", Command(tool: "bun", command: "bun pm cache rm")),
        ("/Library/Caches/Homebrew", Command(tool: "brew", command: "brew cleanup -s --prune=all")),
        ("/.cache/uv", Command(tool: "uv", command: "uv cache clean")),
        ("/Library/Caches/pip", Command(tool: "pip3", command: "pip3 cache purge")),
        ("/.cache/pip", Command(tool: "pip3", command: "pip3 cache purge")),
        ("/Library/Caches/pypoetry", Command(tool: "poetry", command: "poetry cache clear --all . -n")),
        ("/.cache/pre-commit", Command(tool: "pre-commit", command: "pre-commit clean")),
        ("/go/pkg/mod", Command(tool: "go", command: "go clean -modcache")),
        ("/Library/Caches/go-build", Command(tool: "go", command: "go clean -cache")),
        ("/Library/Developer/CoreSimulator/Devices", Command(tool: "xcrun", command: "xcrun simctl delete unavailable")),
        ("/Library/Containers/com.docker.docker", Command(tool: "docker", command: "docker system prune")),
        ("/.cocoapods/repos", Command(tool: "pod", command: "pod cache clean --all")),
        ("/Library/Caches/CocoaPods", Command(tool: "pod", command: "pod cache clean --all")),
    ]

    public static func command(for path: String, home: String) -> Command? {
        guard path.hasPrefix(home) else { return nil }
        let relative = String(path.dropFirst(home.count))
        return table.first { relative == $0.prefix || relative.hasPrefix($0.prefix + "/") }?.command
    }
}
