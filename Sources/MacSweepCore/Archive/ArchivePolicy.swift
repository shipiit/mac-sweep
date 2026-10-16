import Foundation

/// Recognises software projects by the files at their top level.
public enum ProjectMarkers {
    static let byName: [String: String] = [
        ".git": "Git", "package.json": "Node", "Cargo.toml": "Rust", "Package.swift": "Swift", "go.mod": "Go",
        "pyproject.toml": "Python", "requirements.txt": "Python", "setup.py": "Python", "Gemfile": "Ruby",
        "pom.xml": "Java", "build.gradle": "Gradle", "build.gradle.kts": "Gradle", "composer.json": "PHP",
        "CMakeLists.txt": "C/C++", "pubspec.yaml": "Flutter", "mix.exs": "Elixir", "Podfile": "CocoaPods",
    ]
    static let byExtension: [String: String] = ["xcodeproj": "Xcode", "xcworkspace": "Xcode", "sln": ".NET", "csproj": ".NET"]

    /// Regenerable output that can be trashed before archiving ("clean build folders first").
    public static let buildFolderNames: Set<String> = ["node_modules", ".build", "DerivedData", ".next", ".gradle", "Pods"]

    /// Project kinds found among a folder's direct entries, de-duplicated and sorted.
    public static func detect(entries: [String]) -> [String] {
        let kinds = entries.compactMap { entry in
            byName[entry] ?? byExtension[(entry as NSString).pathExtension.lowercased()]
        }
        return Array(Set(kinds)).sorted()
    }
}

/// Rough zip size: already-compressed media barely shrinks, text and code shrink a lot.
public enum CompressionEstimate {
    public enum Kind: Sendable, CaseIterable {
        case compressed, text, other

        var ratio: Double {
            switch self {
            case .compressed: 0.98
            case .text: 0.3
            case .other: 0.6
            }
        }
    }

    static let compressedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "avif", "mp4", "mov", "m4v", "mkv", "avi", "mp3", "m4a",
        "aac", "zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg", "pkg", "ipa", "jar", "docx", "xlsx", "pptx",
        "pdf", "sketch", "psd", "zst", "br",
    ]
    static let textExtensions: Set<String> = [
        "txt", "md", "json", "js", "jsx", "ts", "tsx", "mjs", "cjs", "swift", "py", "rb", "go", "rs", "java", "kt",
        "c", "h", "cc", "cpp", "hpp", "m", "mm", "cs", "php", "html", "htm", "css", "scss", "less", "xml", "plist",
        "yml", "yaml", "toml", "csv", "tsv", "svg", "log", "sql", "sh", "lock", "map", "ini", "cfg", "tex", "rtf",
    ]

    public static func kind(forExtension ext: String) -> Kind {
        let ext = ext.lowercased()
        if compressedExtensions.contains(ext) { return .compressed }
        if textExtensions.contains(ext) { return .text }
        return .other
    }

    public static func estimate(compressed: UInt64, text: UInt64, other: UInt64) -> UInt64 {
        let total = Double(compressed) * Kind.compressed.ratio + Double(text) * Kind.text.ratio + Double(other) * Kind.other.ratio
        return UInt64(total.rounded())
    }
}

/// What a survey learned about one folder.
public struct FolderFacts: Sendable, Equatable {
    public let path: String
    public let markers: [String]
    /// Allocated bytes, build folders included.
    public let size: UInt64
    public let fileCount: Int
    /// Newest modification of any file or folder inside, ignoring build output and `.git` internals.
    public let newestModification: Date?
    public let buildFolders: [CleanupTarget]
    public let estimatedArchiveSize: UInt64
    /// iCloud placeholders inside; archiving would force them to download.
    public let cloudOnlyFiles: Int

    public init(path: String, markers: [String], size: UInt64, fileCount: Int, newestModification: Date?,
                buildFolders: [CleanupTarget] = [], estimatedArchiveSize: UInt64, cloudOnlyFiles: Int = 0) {
        self.path = path
        self.markers = markers
        self.size = size
        self.fileCount = fileCount
        self.newestModification = newestModification
        self.buildFolders = buildFolders
        self.estimatedArchiveSize = estimatedArchiveSize
        self.cloudOnlyFiles = cloudOnlyFiles
    }

    public var name: String { (path as NSString).lastPathComponent }
    public var buildFolderSize: UInt64 { buildFolders.reduce(0) { $0 + $1.size } }
}

public struct ArchiveCriteria: Sendable, Equatable {
    public var minimumIdleDays = 180
    /// Projects smaller than this are not worth offloading.
    public var minimumProjectSize: UInt64 = 20 << 20
    /// Plain (non-project) folders must be at least this big.
    public var minimumFolderSize: UInt64 = 1 << 30

    public init() {}
}

public struct ArchiveCandidate: Sendable, Identifiable, Equatable {
    public enum Reason: Sendable, Equatable {
        case project([String])
        case largeFolder
    }

    public let facts: FolderFacts
    public let reason: Reason
    public let idleDays: Int

    public var id: String { facts.path }
}

public enum ArchivePolicy {
    public static func select(_ facts: [FolderFacts], criteria: ArchiveCriteria, now: Date) -> [ArchiveCandidate] {
        let selected = facts.compactMap { folder -> ArchiveCandidate? in
            guard folder.cloudOnlyFiles == 0, folder.fileCount > 0, let newest = folder.newestModification else { return nil }
            let idleDays = Int(now.timeIntervalSince(newest) / 86_400)
            guard idleDays >= criteria.minimumIdleDays else { return nil }
            if !folder.markers.isEmpty {
                return folder.size >= criteria.minimumProjectSize ? ArchiveCandidate(facts: folder, reason: .project(folder.markers), idleDays: idleDays) : nil
            }
            return folder.size >= criteria.minimumFolderSize ? ArchiveCandidate(facts: folder, reason: .largeFolder, idleDays: idleDays) : nil
        }
        // An idle folder that is offered whole makes its idle sub-projects redundant.
        return selected
            .filter { candidate in !selected.contains { PathTools.isDescendant(candidate.facts.path, of: $0.facts.path) } }
            .sorted { $0.facts.size != $1.facts.size ? $0.facts.size > $1.facts.size : $0.facts.path < $1.facts.path }
    }
}
