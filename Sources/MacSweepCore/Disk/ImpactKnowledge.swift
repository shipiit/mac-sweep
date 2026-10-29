import Foundation

public enum DeletionRisk: String, Sendable, CaseIterable {
    case safe = "Safe to delete"
    case caution = "Think first"
    case keep = "Keep"
}

public struct Explanation: Sendable, Equatable {
    public let summary: String
    public let ifDeleted: String
    public let risk: DeletionRisk

    public init(_ summary: String, ifDeleted: String, risk: DeletionRisk) {
        self.summary = summary
        self.ifDeleted = ifDeleted
        self.risk = risk
    }
}

/// Answers "what is this, and what breaks if I delete it?" for files and folders.
/// Rules are ordered most-specific first; the first match wins.
public enum ImpactKnowledge {
    public static func explain(path: String, home: String) -> Explanation? {
        let lower = path.lowercased()
        let name = (lower as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        for rule in rules where rule.matches(lower, name, ext, home.lowercased()) {
            return rule.explanation
        }
        if let summary = FolderKnowledge.describe(path: path, home: home) {
            return Explanation(summary, ifDeleted: "Depends on the owning app. Check before removing; it goes to the Trash so you can restore it.", risk: .caution)
        }
        return nil
    }

    struct Rule {
        enum Match {
            case contains(String)
            case containsBoth(String, String)
            case name(String)
            case ext([String])
            case under(String)
        }

        let match: Match
        let explanation: Explanation

        func matches(_ path: String, _ name: String, _ ext: String, _ home: String) -> Bool {
            switch match {
            case .contains(let needle): path.contains(needle)
            case .containsBoth(let a, let b): path.contains(a) && path.contains(b)
            case .name(let exact): name == exact
            case .ext(let list): list.contains(ext)
            case .under(let relative): path == home + relative || path.hasPrefix(home + relative + "/")
            }
        }
    }

    static func rule(_ match: Rule.Match, _ summary: String, _ ifDeleted: String, _ risk: DeletionRisk) -> Rule {
        Rule(match: match, explanation: Explanation(summary, ifDeleted: ifDeleted, risk: risk))
    }

    static let rules: [Rule] = toolRules + specificRules + genericToolRules + locationRules + extensionRules

    /// Broad patterns that must lose to every specific rule above them.
    static let genericToolRules: [Rule] = [
        rule(.ext(["pth", "pt", "safetensors", "ckpt", "gguf", "onnx", "mlmodel", "bin"]),
             "Machine-learning model weights.",
             "Whatever uses this model must download or train it again. Safe if you no longer use it.", .caution),
        rule(.name("vectors"),
             "Vector index data for a local search or AI tool.", "That tool rebuilds its index, which can take a while.", .caution),
        rule(.contains("/.cache/"),
             "A cache kept by a command-line tool.", "The tool re-downloads or rebuilds what it needs. Nothing else breaks.", .safe),
    ]

    /// Developer and AI tool files that otherwise show up as "Unknown" in Large Files.
    static let toolRules: [Rule] = [
        rule(.containsBoth("/.git/", "/pack/"),
             "Part of a git repository's history (compressed objects).",
             "The repository breaks: commits and files become unreadable. Shrink it with `git gc` instead.", .keep),
        rule(.contains("/.local/share/claude/versions/"),
             "A Claude Code CLI build kept for rollback.", "Nothing breaks if it isn't the version you run; the newest is used.", .safe),
        rule(.contains("/.cache/codex-runtimes/codex-runtime-install-"),
             "A leftover from an interrupted Codex runtime download.", "Nothing breaks. Codex uses its finished runtime.", .safe),
        rule(.contains("/.cache/codex-runtimes/"),
             "The runtime Codex uses to run tasks.", "Codex downloads it again the next time it runs a task.", .caution),
        rule(.containsBoth("/.vscode", "/extensions/"),
             "Part of an installed VS Code extension (bundled tools or binaries).",
             "That extension stops working until you reinstall it. Old versions of updated extensions are safe to remove.", .caution),
        rule(.containsBoth("/.cursor", "/extensions/"),
             "Part of an installed Cursor extension.", "That extension stops working until you reinstall it.", .caution),
        rule(.contains("/.codex/"),
             "Codex data: sessions, history database or its app components.",
             "Codex loses that history or re-downloads the component. Your code is not affected.", .caution),
        rule(.contains("/.roboflow/models/"),
             "A downloaded Roboflow computer-vision model.", "Downloaded again the next time your code loads that model.", .caution),
    ]

    static let specificRules: [Rule] = [
        rule(.contains("/application support/claude/vm_bundles"),
             "Claude desktop app's sandbox virtual machine (Linux disk images used to run code).",
             "Claude rebuilds or re-downloads the VM next time it needs it. Anything saved inside past VM sessions is lost. Quit Claude first.", .caution),
        rule(.contains("/optguideondevicemodel"),
             "Chrome's built-in on-device AI model (Gemini Nano), used for features like writing help and scam detection.",
             "Chrome downloads it again unless you turn off on-device AI in chrome://settings/system. Nothing else breaks.", .safe),
        rule(.contains("/optguideondeviceclassifiermodel"),
             "Chrome's on-device classifier model.", "Chrome re-downloads it when needed. Nothing else breaks.", .safe),
        rule(.contains("/googleupdater/crx_cache"),
             "Cached Chrome and extension update downloads.", "Nothing breaks. Updates are re-downloaded if needed.", .safe),
        rule(.containsBoth("/.claude/projects/", ".jsonl"),
             "A Claude Code conversation transcript.",
             "You can no longer `/resume` that conversation or search its history. Your code is not affected.", .caution),
        rule(.contains("/.claude/worktrees/"),
             "A git worktree created by a Claude Code agent.",
             "Uncommitted or unpushed changes in it are lost. Check `git status` there first.", .caution),
        rule(.contains("/@anthropic-ai/claude-code"),
             "The Claude Code CLI, installed with npm for this Node version.",
             "The `claude` command stops working for this Node version until you reinstall it. Keep it if you use Claude Code.", .keep),
        rule(.contains("/.nvm/versions/node/"),
             "A Node.js version installed by nvm, with its global npm packages.",
             "Projects and global tools that use this Node version stop working until you `nvm install` it again.", .caution),
        rule(.contains("com_apple_mobileasset"),
             "An asset macOS downloaded on its own (Siri voices, dictation, fonts, language models).",
             "macOS re-downloads it when a feature needs it; that feature may not work offline until then. Usually best left to macOS.", .caution),
        rule(.contains("uc_siri_asr"),
             "Siri and dictation speech-recognition model downloaded by macOS.",
             "Offline dictation and Siri speech recognition stop until macOS re-downloads it.", .caution),
        rule(.name("docker.raw"),
             "Docker Desktop's virtual disk with every image, container and volume.",
             "All containers and volumes are lost, including any databases in them. Use `docker system prune` instead.", .keep),
        rule(.ext(["photoslibrary"]),
             "Your Photos library.", "All photos not synced to iCloud are lost. Never delete it from Finder; manage it in Photos.", .keep),
        rule(.contains("/library/messages/attachments"),
             "Photos and files sent or received in Messages.", "Those attachments disappear from your conversations.", .keep),
        rule(.contains("/mobilesync/backup"),
             "An iPhone or iPad backup made by Finder.", "You can't restore that device from this backup. Delete only old devices' backups.", .caution),
        rule(.contains("/.ssh"), "Your SSH keys and config.", "You lose access to servers and Git hosts that use these keys.", .keep),
        rule(.name(".git"), "This project's Git history.", "All local history, branches and unpushed commits are lost.", .keep),
    ]

    static let locationRules: [Rule] = [
        rule(.contains("/library/developer/xcode/deriveddata"),
             "Xcode build products and indexes.", "Next Xcode build takes longer. Nothing else breaks.", .safe),
        rule(.contains("devicesupport"),
             "Debug symbols for iOS versions you've connected.", "Xcode copies them again the next time that device connects.", .safe),
        rule(.contains("/library/developer/coresimulator/devices"),
             "iOS simulator devices and the apps installed in them.", "Simulators and their data are reset; recreate them in Xcode.", .caution),
        rule(.contains("/node_modules"),
             "Installed JavaScript dependencies.", "The project won't run until you `npm install` / `pnpm install` again.", .safe),
        rule(.contains("/.ollama/models"),
             "Local LLM weights for Ollama.", "Those models must be pulled again with `ollama pull` (several GB each).", .caution),
        rule(.contains("/.cache/huggingface"),
             "Downloaded Hugging Face models and datasets.", "They're re-downloaded the next time code loads them.", .caution),
        rule(.contains("/library/caches/"),
             "A rebuildable app cache.", "The app recreates it. The next launch may be a little slower.", .safe),
        rule(.contains("/library/logs/"),
             "Log files.", "Nothing breaks. You lose old diagnostics.", .safe),
        rule(.contains("/.trash/"),
             "Something already in the Trash.", "Deleting it here is permanent.", .safe),
        rule(.contains("/library/containers/"),
             "Private data of a sandboxed app.", "That app loses its settings and possibly documents. Uninstall the app instead.", .keep),
        rule(.contains("/library/group containers/"),
             "Data shared between apps from one developer.", "Those apps may lose settings or documents.", .keep),
        rule(.contains("/library/application support/"),
             "Data an app keeps between launches.", "The app may lose settings, logins or downloaded content.", .caution),
    ]

    static let extensionRules: [Rule] = [
        rule(.ext(["dmg", "pkg", "xip", "iso"]),
             "An installer or disk image.", "Nothing breaks if the app is already installed.", .safe),
        rule(.ext(["zip", "tar", "gz", "tgz", "rar", "7z"]),
             "A compressed archive.", "You lose its contents unless you extracted them somewhere.", .caution),
        rule(.ext(["gguf", "safetensors", "onnx", "pt", "ckpt"]),
             "Machine-learning model weights.", "The tool that uses this model re-downloads it or stops working.", .caution),
        rule(.ext(["mp4", "mov", "mkv", "avi", "m4v"]),
             "A video file.", "The video is gone once the Trash is emptied.", .caution),
        rule(.ext(["sqlite", "db", "realm"]),
             "A database file belonging to an app.", "The app loses the data stored in it.", .keep),
        rule(.ext(["log"]), "A log file.", "Nothing breaks.", .safe),
        rule(.ext(["jsonl"]), "Line-by-line JSON data, often logs or chat transcripts.", "Whatever reads it loses that history.", .caution),
        rule(.ext(["img", "raw", "vmdk", "qcow2", "vdi", "sparseimage", "sparsebundle"]),
             "A virtual machine or disk image.", "The VM or disk it belongs to stops working; its contents are lost.", .caution),
        rule(.ext(["app"]), "An application.", "The app is uninstalled; its data in Library stays behind.", .caution),
    ]
}
