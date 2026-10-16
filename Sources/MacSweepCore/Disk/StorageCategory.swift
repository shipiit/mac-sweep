import Foundation

public enum StorageCategory: String, CaseIterable, Sendable, Identifiable {
    case media = "Documents & media"
    case code = "Code projects"
    case devTools = "Dev tools & other"
    case sdks = "iOS & Android SDKs"
    case ai = "AI models"
    case caches = "Package caches"
    case system = "Apps & system"
    case other = "Other"

    public var id: String { rawValue }

    /// Returns the category a path clearly belongs to, or nil when it should inherit its parent's.
    public static func classify(path: String, home: String, isGitRepo: Bool = false) -> StorageCategory? {
        let lower = path.lowercased()
        let homeLower = home.lowercased()

        if !lower.hasPrefix(homeLower + "/") {
            return systemRoots.contains { lower == $0 || lower.hasPrefix($0 + "/") } ? .system : nil
        }
        let rel = String(lower.dropFirst(homeLower.count))
        func under(_ prefixes: [String]) -> Bool {
            prefixes.contains { rel == $0 || rel.hasPrefix($0 + "/") }
        }

        if under(aiPaths) { return .ai }
        if under(sdkPaths) { return .sdks }
        if under(cachePaths) { return .caches }
        if (rel as NSString).lastPathComponent == "node_modules" { return .caches }
        if isGitRepo { return .code }
        if under(codePaths) { return .code }
        if under(mediaPaths) { return .media }
        if under(["/library", "/applications"]) { return .system }
        let components = rel.split(separator: "/")
        if components.count == 1, components[0].hasPrefix(".") { return .devTools }
        return nil
    }

    private static let systemRoots = ["/applications", "/system", "/library", "/usr", "/private", "/opt", "/bin", "/sbin"]

    private static let aiPaths = [
        "/.ollama", "/.lmstudio", "/.cache/lm-studio", "/.cache/huggingface", "/.cache/torch",
        "/library/application support/nomic.ai", "/library/application support/jan",
    ]

    private static let sdkPaths = [
        "/library/developer", "/library/android", "/.android", "/.swiftpm",
    ]

    private static let cachePaths = [
        "/.npm", "/.gradle", "/.cache", "/library/caches", "/.m2", "/.cargo", "/go/pkg", "/.pnpm-store",
        "/library/pnpm", "/.bun", "/.yarn", "/.cocoapods", "/.pub-cache", "/.nuget", "/.rustup",
    ]

    private static let codePaths = [
        "/desktop", "/projects", "/code", "/dev", "/src", "/developer", "/github", "/repos", "/workspace",
        "/cascadeprojects", "/go/src",
    ]

    private static let mediaPaths = [
        "/documents", "/pictures", "/movies", "/music", "/downloads", "/public",
        "/library/mobile documents", "/library/cloudstorage",
    ]
}
