import Foundation
import os

/// Walks folders for programs, installers and scripts, gathers their facts and runs `ThreatRules`.
/// App bundles are checked as a whole and never descended into.
public enum ThreatScanner {
    private static let log = Logger(subsystem: Log.subsystem, category: "threats")
    static let skippedNames: Set<String> = ["node_modules", ".git", "Library", ".Trash", "DerivedData", ".build", "Pods", ".npm", ".cache"]
    static let bundleExtensions: Set<String> = ["app", "photoslibrary", "framework", "bundle", "plugin", "xcarchive", "musiclibrary"]

    public static func defaultRoots(home: String = NSHomeDirectory()) -> [String] {
        [home + "/Downloads", home + "/Desktop", home + "/Documents", home + "/Applications", "/Applications", "/Users/Shared", "/private/tmp"]
    }

    public struct Progress: Sendable, Equatable {
        public var filesSeen = 0
        public var candidates = 0
        public var currentPath = ""
    }

    public static func scan(roots: [String], maxFiles: Int = 400_000, progress: (@Sendable (Progress) -> Void)? = nil) async -> [ThreatVerdict] {
        var paths: [String] = []
        var state = Progress()
        for root in roots {
            walk(root) { path in
                state.filesSeen += 1
                if state.filesSeen % 2_000 == 0 { state.currentPath = path; progress?(state) }
                if isCandidate(path) { paths.append(path) }
                return state.filesSeen < maxFiles && !Task.isCancelled
            }
        }
        state.candidates = paths.count
        progress?(state)
        let verdicts = await Concurrent.map(paths, limit: 4) { path -> ThreatVerdict? in
            Task.isCancelled ? nil : facts(for: path).flatMap(ThreatRules.assess)
        }
        log.info("Threat scan: \(state.filesSeen) files, \(paths.count) checked, \(verdicts.compactMap { $0 }.count) flagged")
        return verdicts.compactMap { $0 }.sorted { ($0.severity, $1.facts.path) > ($1.severity, $0.facts.path) }
    }

    /// Apple's own templates and sample apps ship unsigned on purpose.
    static let trustedPrefixes = ["/Library/Application Support/Script Editor/", "/System/"]

    /// Calls `visit` for every file (and every real app bundle as one item); stop by returning false.
    /// Each step runs in its own autorelease pool so walking millions of files stays at a flat memory cost.
    static func walk(_ root: String, visit: (String) -> Bool) {
        guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                              options: [], errorHandler: { _, _ in true }) else { return }
        var keepGoing = true
        while keepGoing {
            keepGoing = autoreleasepool { () -> Bool in
                guard let url = enumerator.nextObject() as? URL else { return false }
                let name = url.lastPathComponent
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { return true }
                if values?.isDirectory == true {
                    if skippedNames.contains(name) || trustedPrefixes.contains(where: url.path.hasPrefix) {
                        enumerator.skipDescendants()
                        return true
                    }
                    let ext = url.pathExtension.lowercased()
                    if bundleExtensions.contains(ext) {
                        enumerator.skipDescendants()
                        if ext == "app", isAppBundle(url.path) { return visit(url.path) }
                    }
                    return true
                }
                return visit(url.path)
            }
        }
    }

    /// A folder named *.app is only an app if it has the bundle structure.
    static func isAppBundle(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/Contents/Info.plist") || FileManager.default.fileExists(atPath: path + "/Contents/MacOS")
    }

    public static func isCandidate(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "app" || ext == "pkg" || ext == "mpkg" || FileKind.runOnOpenExtensions.contains(ext) { return true }
        if FileKind.documentExtensions.contains(ext) { return ThreatRules.isDisguised((path as NSString).lastPathComponent) }
        return FileManager.default.isExecutableFile(atPath: path) && isMachO(path)
    }

    static func isMachO(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let magic = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return [0xFEEDFACF, 0xCFFAEDFE, 0xFEEDFACE, 0xCEFAEDFE, 0xCAFEBABE, 0xBEBAFECA].contains(magic)
    }

    /// Facts for one file. Gatekeeper is only asked about downloaded apps and installers (it is slow).
    public static func facts(for path: String) -> FileFacts? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let name = (path as NSString).lastPathComponent
        let kind = FileKind.classify(name: name, isExecutable: FileManager.default.isExecutableFile(atPath: path), isMachO: isMachO(path))
        let quarantine = extendedAttribute("com.apple.quarantine", path: path)
        let signature: SignatureStatus? = switch kind {
        case .app, .executable: CodeSignature.check(path: path)
        case .installerPackage: packageSignature(path)
        default: nil
        }
        var gatekeeper = GatekeeperVerdict.notChecked
        if quarantine != nil, kind == .app || kind == .installerPackage {
            gatekeeper = assessGatekeeper(path, isInstaller: kind == .installerPackage)
        }
        return FileFacts(path: path, kind: kind, signature: signature, gatekeeper: gatekeeper, origin: origin(path),
                         isQuarantined: quarantine != nil, size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0)
    }

    static func extendedAttribute(_ name: String, path: String) -> Data? {
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, length, 0, 0) }
        return read > 0 ? data : nil
    }

    /// The first "where from" URL Safari/Chrome recorded for a download.
    static func origin(_ path: String) -> String? {
        guard let data = extendedAttribute("com.apple.metadata:kMDItemWhereFroms", path: path),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] else { return nil }
        return list.first
    }

    static func packageSignature(_ path: String) -> SignatureStatus {
        guard let result = try? Shell.runBlocking("/usr/sbin/pkgutil", ["--check-signature", path]) else { return .missing }
        return parsePackageSignature(result.stdout, status: result.status)
    }

    static func parsePackageSignature(_ output: String, status: Int32) -> SignatureStatus {
        let text = output.lowercased()
        if text.contains("no signature") { return .unsigned }
        if status != 0 || text.contains("invalid") || text.contains("revoked") { return .invalid }
        if text.contains("signed by a certificate trusted by mac os") || text.contains("signed apple software") { return .apple }
        if let range = output.range(of: #"\(([A-Z0-9]{10})\)"#, options: .regularExpression) {
            return .developer(teamID: String(output[range].dropFirst().dropLast()))
        }
        return text.contains("signed") ? .developer(teamID: "?") : .unsigned
    }

    static func assessGatekeeper(_ path: String, isInstaller: Bool) -> GatekeeperVerdict {
        guard let result = try? Shell.runBlocking("/usr/sbin/spctl", ["--assess", "--type", isInstaller ? "install" : "execute", "-vv", path]) else {
            return .notChecked
        }
        return parseGatekeeper(result.stderr + result.stdout, status: result.status)
    }

    static func parseGatekeeper(_ output: String, status: Int32) -> GatekeeperVerdict {
        if status == 0 { return .accepted }
        let reason = output.split(separator: "\n").first { $0.contains("rejected") || $0.contains("source=") }
            .map { String($0).replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces) }
        return .rejected(reason?.components(separatedBy: ": ").last ?? "not allowed to run")
    }
}
