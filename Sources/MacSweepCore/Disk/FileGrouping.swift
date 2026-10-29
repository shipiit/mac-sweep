import Foundation

/// Plain-language groups for the Large & Hidden Files list.
public enum FileGroup: String, CaseIterable, Sendable, Identifiable {
    case ai = "AI sessions & models"
    case developer = "Developer files"
    case appData = "App data"
    case media = "Photos, video & music"
    case downloads = "Downloads & installers"
    case system = "macOS assets & caches"
    case documents = "Documents"
    case other = "Other"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .ai: "sparkles"
        case .developer: "hammer"
        case .appData: "square.stack.3d.up"
        case .media: "photo.on.rectangle"
        case .downloads: "arrow.down.circle"
        case .system: "gearshape.2"
        case .documents: "doc.text"
        case .other: "questionmark.folder"
        }
    }

    static let mediaExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "jpg", "jpeg", "png", "heic", "gif", "raw", "cr2", "mp3", "m4a", "wav", "aiff", "flac"]
    static let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "zip", "xip", "ipsw"]
    static let modelExtensions: Set<String> = ["pth", "pt", "safetensors", "ckpt", "gguf", "onnx", "mlmodel"]

    /// The group for a path under `home`; the first matching check wins.
    public static func of(path: String, home: String) -> FileGroup {
        let lower = path.lowercased()
        let relative = path.hasPrefix(home) ? String(lower.dropFirst(home.count)) : lower
        let ext = (lower as NSString).pathExtension
        if relative.hasPrefix("/.claude/") || relative.hasPrefix("/.codex/") || relative.hasPrefix("/.ollama/") || relative.hasPrefix("/.roboflow/")
            || lower.contains("/huggingface/") || lower.contains("/lm-studio") || lower.contains("/application support/claude/")
            || modelExtensions.contains(ext) { return .ai }
        if relative.hasPrefix("/library/developer/") || relative.hasPrefix("/.vscode") || relative.hasPrefix("/.cursor") || relative.hasPrefix("/.cache/")
            || relative.hasPrefix("/.npm") || relative.hasPrefix("/.nvm") || relative.hasPrefix("/.gradle") || relative.hasPrefix("/.m2")
            || relative.hasPrefix("/.cargo") || relative.hasPrefix("/go/") || relative.hasPrefix("/library/pnpm") || lower.contains("/.git/")
            || lower.contains("/node_modules/") || lower.contains("/.venv/") { return .developer }
        if relative.hasPrefix("/downloads/") || installerExtensions.contains(ext) { return .downloads }
        if relative.hasPrefix("/library/caches/") || relative.hasPrefix("/library/metadata/") || lower.contains("/com.apple.")
            || lower.contains("/assets/") && relative.hasPrefix("/library/") { return .system }
        if relative.hasPrefix("/pictures/") || relative.hasPrefix("/movies/") || relative.hasPrefix("/music/") || mediaExtensions.contains(ext) { return .media }
        if relative.hasPrefix("/library/") { return .appData }
        if relative.hasPrefix("/documents/") || relative.hasPrefix("/desktop/") { return .documents }
        return .other
    }
}
