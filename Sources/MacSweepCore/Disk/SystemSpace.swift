import Foundation

/// The parts of the disk a home-folder scan never sees, each measured and explained.
public struct SystemSpaceBucket: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case applications, homebrew, databases, simulatorRuntimes, tempFiles, browserCopies, swap, updateSnapshots
    }

    public let kind: Kind
    public let size: UInt64
    /// For things without a measurable size (update snapshots), a count instead.
    public let count: Int?
    public var id: String { kind.rawValue }

    public init(kind: Kind, size: UInt64, count: Int? = nil) {
        self.kind = kind
        self.size = size
        self.count = count
    }
}

public extension SystemSpaceBucket.Kind {
    var title: String {
        switch self {
        case .applications: "Applications"
        case .homebrew: "Homebrew packages"
        case .databases: "Local databases"
        case .simulatorRuntimes: "Simulator runtimes"
        case .tempFiles: "Temporary files"
        case .browserCopies: "Browser code-sign copies"
        case .swap: "Swap (virtual memory)"
        case .updateSnapshots: "macOS update snapshots"
        }
    }

    var explanation: String {
        switch self {
        case .applications: "Apps in /Applications. Remove apps you don't use with Uninstaller; App Footprint shows their data too."
        case .homebrew: "Tools installed with brew. `brew cleanup` removes old versions; uninstall formulae you no longer need."
        case .databases: "Postgres, MySQL and Redis data under Homebrew. Old test databases are often most of it."
        case .simulatorRuntimes: "Each iOS, watchOS or visionOS simulator version is a large disk image. Xcode re-downloads one when needed."
        case .tempFiles: "Your per-user temp and cache folders in /var/folders. macOS clears most of it at restart."
        case .browserCopies: "Chrome, Brave and Edge copy themselves here at launch and leave the copy behind after a crash or force-quit."
        case .swap: "Memory macOS moved to disk. It goes away when you restart; quitting heavy apps keeps it small."
        case .updateSnapshots: "Snapshots macOS takes before an update. Installing or finishing the pending update removes them."
        }
    }

    var symbol: String {
        switch self {
        case .applications: "app.dashed"
        case .homebrew: "mug"
        case .databases: "cylinder.split.1x2"
        case .simulatorRuntimes: "iphone"
        case .tempFiles: "clock.arrow.2.circlepath"
        case .browserCopies: "doc.on.doc"
        case .swap: "memorychip"
        case .updateSnapshots: "camera.on.rectangle"
        }
    }
}

public enum SystemSpace {
    /// `vm.swapusage: total = 10240.00M  used = 8940.69M  free = 1299.31M  (encrypted)` → the swap files' size.
    public static func swapBytes(sysctlOutput: String) -> UInt64? {
        guard let range = sysctlOutput.range(of: "total = ") else { return nil }
        let value = sysctlOutput[range.upperBound...].prefix { !$0.isWhitespace }
        guard let unit = value.last, let number = Double(value.dropLast()) else { return nil }
        let scale: Double = switch unit {
        case "K": 1_024
        case "M": 1_048_576
        case "G": 1_073_741_824
        default: 0
        }
        return scale > 0 ? UInt64(number * scale) : nil
    }

    /// Counts `com.apple.os.update-…` lines from `tmutil listlocalsnapshots /`.
    public static func updateSnapshotCount(tmutilOutput: String) -> Int {
        tmutilOutput.split(separator: "\n").filter { $0.hasPrefix("com.apple.os.update-") }.count
    }

    /// Homebrew's prefix on Apple Silicon or Intel.
    public static func homebrewPrefix() -> String? {
        ["/opt/homebrew", "/usr/local"].first { FileManager.default.fileExists(atPath: $0 + "/Cellar") }
    }

    /// The folders a bucket is made of, so its contents can be listed.
    public static func roots(for kind: SystemSpaceBucket.Kind, brewPrefix: String? = homebrewPrefix(), tempRoot: String? = CodeSignClones.userTempRoot()) -> [String] {
        switch kind {
        case .applications: ["/Applications"]
        case .homebrew: brewPrefix.map { [$0 + "/Cellar", $0 + "/Caskroom"] } ?? []
        case .databases: brewPrefix.map { [$0 + "/var"] } ?? []
        case .simulatorRuntimes: ["/Library/Developer/CoreSimulator"]
        case .tempFiles: tempRoot.map { [$0 + "/T", $0 + "/C"] } ?? []
        case .browserCopies: tempRoot.map { [$0 + "/X"] } ?? []
        case .swap: ["/private/var/vm"]
        case .updateSnapshots: []
        }
    }

    /// Measures everything outside home. Slow parts (Applications, Homebrew) run in parallel.
    public static func measure(runtimesSize: UInt64, clones: [CodeSignClone], measure: @escaping @Sendable (String) -> UInt64? = { DiskScanner.measure($0) }) async -> [SystemSpaceBucket] {
        let brew = homebrewPrefix()
        async let applications = Task.detached(priority: .utility) { measure("/Applications") ?? 0 }.value
        async let homebrew = Task.detached(priority: .utility) {
            guard let brew else { return UInt64(0) }
            return ["Cellar", "Caskroom"].reduce(UInt64(0)) { $0 + (measure(brew + "/" + $1) ?? 0) }
        }.value
        async let databases = Task.detached(priority: .utility) { brew.flatMap { measure($0 + "/var") } ?? 0 }.value
        async let temp = Task.detached(priority: .utility) { CodeSignClones.userTempRoot().flatMap(measure) ?? 0 }.value
        let swap = (try? await Shell.run("/usr/sbin/sysctl", ["vm.swapusage"])).flatMap { swapBytes(sysctlOutput: $0.stdout) } ?? 0
        let snapshots = (try? await Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])).map { updateSnapshotCount(tmutilOutput: $0.stdout) } ?? 0
        let cloneBytes = clones.reduce(UInt64(0)) { $0 + $1.size }
        let tempBytes = await temp
        return [
            SystemSpaceBucket(kind: .applications, size: await applications),
            SystemSpaceBucket(kind: .homebrew, size: await homebrew),
            SystemSpaceBucket(kind: .databases, size: await databases),
            SystemSpaceBucket(kind: .simulatorRuntimes, size: runtimesSize),
            SystemSpaceBucket(kind: .browserCopies, size: cloneBytes, count: clones.count),
            SystemSpaceBucket(kind: .tempFiles, size: tempBytes > cloneBytes ? tempBytes - cloneBytes : 0),
            SystemSpaceBucket(kind: .swap, size: swap),
            SystemSpaceBucket(kind: .updateSnapshots, size: 0, count: snapshots),
        ]
    }
}
