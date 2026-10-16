import Foundation

/// Plain-English explanations of well-known folders, shown when hovering or inspecting a tile.
public enum FolderKnowledge {
    /// Most specific match wins: entries are matched against the home-relative path, then the folder name.
    public static func describe(path: String, home: String) -> String? {
        if PathTools.isDescendant(path, of: home) || path == home {
            let relative = path == home ? "" : String(path.dropFirst(home.count + 1))
            if let text = byRelativePath[relative] { return text }
            if relative.hasPrefix("Library/Containers/") || relative.hasPrefix("Library/Group Containers/") {
                return "Private data of a sandboxed app (settings, caches, documents). Remove the app, not this folder."
            }
            if relative.hasPrefix("Library/Application Support/"), relative.split(separator: "/").count == 3 {
                return "Data an app keeps between launches: databases, downloads, sometimes large caches."
            }
        }
        if path.contains("/.nvm/versions/node/"), path.contains("/lib/node_modules") {
            if path.hasSuffix("/claude.exe") || path.contains("/@anthropic-ai/claude-code") {
                return "Claude Code CLI, installed globally with npm for this Node version. Needed to run `claude`; keep only one install."
            }
            return "A global npm package (npm i -g) installed for this nvm Node version."
        }
        let name = (path as NSString).lastPathComponent
        if let text = byName[name] { return text }
        if let text = byExtension[(name as NSString).pathExtension.lowercased()] { return text }
        if path.hasSuffix(".app") { return "An application bundle. Uninstall it by moving it to the Trash." }
        if path.hasSuffix(".photoslibrary") { return "Your Photos library. Manage it in Photos; never delete it from Finder." }
        return nil
    }

    static let byRelativePath: [String: String] = [
        "": "Your home folder.",
        "Library": "Hidden per-user system folder: app data, caches, preferences, mail and SDKs.",
        "Library/Caches": "Rebuildable caches. Apps recreate these; clearing them costs only a slower first launch.",
        "Library/Application Support": "Persistent data for apps: databases, plugins, models, downloaded content.",
        "Library/Containers": "Sandboxed apps' private folders (Mail, Messages, App Store apps).",
        "Library/Group Containers": "Data shared between apps from the same developer (Office, iCloud apps).",
        "Library/Developer": "Xcode data: DerivedData, simulators, device symbols and archives.",
        "Library/Developer/Xcode/DerivedData": "Xcode's build products and indexes. Safe to clear; Xcode rebuilds it.",
        "Library/Developer/CoreSimulator": "iOS simulator devices and runtimes.",
        "Library/Android": "Android SDK, platform tools and system images.",
        "Library/Logs": "Diagnostic logs from apps and the system. Safe to clear.",
        "Library/Mail": "Your Mail messages and attachments. Don't remove by hand.",
        "Library/Messages": "Your iMessage history and attachments.",
        "Library/Mobile Documents": "iCloud Drive. Deleting here deletes from all your devices.",
        "Library/CloudStorage": "Files synced by Dropbox, Google Drive, OneDrive and other providers.",
        "Library/Application Support/MobileSync": "iPhone and iPad backups made by Finder.",
        ".Trash": "Items in the Trash. Space is freed only when you empty it.",
        ".npm": "npm's download cache and npx installs.",
        ".cache": "Shared cache folder used by many CLI tools (uv, pip, Hugging Face, Puppeteer…).",
        ".gradle": "Gradle dependency and build caches for Android/Java builds.",
        ".android": "Android emulator images (AVDs) and tool settings.",
        ".ollama": "Ollama's local LLM model weights.",
        ".nvm": "Node.js versions installed by nvm. Remove versions with `nvm uninstall`.",
        ".pyenv": "Python versions installed by pyenv. Remove versions with `pyenv uninstall`.",
        ".rustup": "Rust toolchains. Manage with `rustup toolchain list/uninstall`.",
        ".cargo": "Rust's crate registry and installed binaries.",
        ".m2": "Maven's local repository of Java dependencies.",
        ".docker": "Docker CLI settings. The actual images live in Docker Desktop's disk image.",
        ".vscode": "VS Code extensions.",
        ".cursor": "Cursor extensions and settings.",
        ".claude": "Claude Code settings, history and worktrees.",
        ".codex": "Codex CLI sessions and settings.",
        ".ssh": "Your SSH keys. Never delete.",
        ".local": "User-level installs for CLI tools (pipx, uv tools, pnpm).",
        ".bun": "Bun runtime and its package cache.",
        ".pnpm-store": "pnpm's content-addressed package store.",
        ".cocoapods": "CocoaPods spec repositories.",
        ".pub-cache": "Dart & Flutter package cache.",
        "go": "Go workspace: module cache in go/pkg/mod, sources in go/src.",
        "Desktop": "Files on your desktop.",
        "Documents": "Your documents. May be synced to iCloud.",
        "Downloads": "Downloaded files. Old installers (.dmg, .pkg, .zip) are usually safe to remove.",
        "Movies": "Video files and Final Cut/iMovie libraries.",
        "Pictures": "Photos library and images.",
        "Music": "Music library and GarageBand/Logic projects.",
    ]

    static let byExtension: [String: String] = [
        "dmg": "Disk image, usually an app installer. Safe to delete once the app is installed.",
        "pkg": "Installer package. Safe to delete after installing.",
        "zip": "Compressed archive.",
        "xip": "Signed archive, typically an Xcode download. Delete after extracting.",
        "iso": "Disk image of an operating system or installer.",
        "ipsw": "iPhone/iPad firmware download. Safe to delete; Finder re-downloads when needed.",
        "gguf": "Quantised LLM weights (llama.cpp, LM Studio, Ollama).",
        "safetensors": "Machine-learning model weights.",
        "bin": "Binary data, often model weights or firmware.",
        "pt": "PyTorch model checkpoint.",
        "onnx": "ONNX machine-learning model.",
        "vmdk": "Virtual machine disk.",
        "qcow2": "Virtual machine disk (QEMU/UTM).",
        "raw": "Raw disk image, e.g. Docker Desktop's Docker.raw holding all containers and images.",
        "sparseimage": "Growable disk image.",
        "sqlite": "SQLite database used by an app.",
        "db": "Database file used by an app.",
        "log": "Log file. Safe to delete.",
        "mov": "QuickTime video.",
        "mp4": "Video file.",
        "mkv": "Video file.",
        "psd": "Photoshop document.",
        "tar": "Tape archive.",
        "gz": "Gzip-compressed file.",
        "exe": "Executable program (on macOS usually a cross-platform CLI shipped via npm).",
        "app": "An application bundle.",
        "photoslibrary": "Your Photos library. Manage it in Photos; never delete it from Finder.",
        "xcarchive": "Archived Xcode build, used for App Store uploads and crash symbolication.",
        "asar": "Packaged Electron app resources.",
        "node": "Native Node.js addon.",
        "dylib": "Dynamic library.",
        "jar": "Java archive.",
    ]

    static let byName: [String: String] = [
        "claude.exe": "Claude Code CLI binary. Needed to run `claude`.",
        "Docker.raw": "Docker Desktop's virtual disk with all images, containers and volumes. Shrink it with `docker system prune`.",
        "sleepimage": "Copy of RAM written on sleep. Managed by macOS.",
        ".DS_Store": "Finder view settings for a folder. Harmless.",
        "package-lock.json": "npm lockfile. Keep it in the project.",
        "node_modules": "Installed JavaScript dependencies. Recreated by `npm install` / `pnpm install`.",
        ".next": "Next.js build output. Regenerated by `next build` or `next dev`.",
        ".turbo": "Turborepo cache.",
        ".venv": "Python virtual environment. Recreate with `uv sync` or `pip install -r`.",
        "venv": "Python virtual environment.",
        "__pycache__": "Compiled Python bytecode. Regenerated automatically.",
        "DerivedData": "Xcode build products.",
        "Pods": "CocoaPods dependencies. Recreated by `pod install`.",
        ".dart_tool": "Dart/Flutter build cache. Recreated by `flutter pub get`.",
        "build": "Build output folder. Usually regenerated by the project's build.",
        "dist": "Packaged build output.",
        "target": "Build output (Rust/Cargo or Maven).",
        ".git": "Git history for this project.",
        "worktrees": "Extra git checkouts. Check for unpushed work before removing.",
        "Cache": "An app's web/network cache. Safe to clear while the app is closed.",
        "Code Cache": "Compiled JavaScript cache from an Electron/Chromium app.",
        "GPUCache": "Shader cache from an Electron/Chromium app.",
    ]
}
