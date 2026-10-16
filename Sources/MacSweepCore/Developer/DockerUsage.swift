import Foundation

public enum DockerResourceKind: String, Sendable, CaseIterable, Identifiable {
    case images = "Images"
    case containers = "Containers"
    case volumes = "Volumes"
    case buildCache = "Build cache"

    public var id: String { rawValue }

    /// Maps the `Type` column of `docker system df`.
    static func from(_ type: String) -> DockerResourceKind? {
        switch type.lowercased() {
        case "images": .images
        case "containers": .containers
        case "local volumes", "volumes": .volumes
        case "build cache": .buildCache
        default: nil
        }
    }
}

public struct DockerUsageRow: Sendable, Equatable, Identifiable {
    public let kind: DockerResourceKind
    public let total: Int
    public let active: Int
    public let size: UInt64
    public let reclaimable: UInt64

    public var id: String { kind.id }

    public init(kind: DockerResourceKind, total: Int, active: Int, size: UInt64, reclaimable: UInt64) {
        self.kind = kind
        self.total = total
        self.active = active
        self.size = size
        self.reclaimable = reclaimable
    }
}

public struct DockerImage: Sendable, Equatable, Identifiable {
    public let id: String
    public let repository: String
    public let tag: String
    public let size: UInt64
    public let containers: Int
    public let created: String

    public var isDangling: Bool { repository == "<none>" || repository.isEmpty }
    public var displayName: String { isDangling ? "<untagged> \(id.prefix(19))" : "\(repository):\(tag)" }
}

public struct DockerContainer: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let image: String
    public let state: String
    public let status: String
    public let size: UInt64

    public var isRunning: Bool { state.lowercased() == "running" }
}

public struct DockerVolume: Sendable, Equatable, Identifiable {
    public let name: String
    public let links: Int
    public let size: UInt64

    public var id: String { name }
    public var isUnused: Bool { links == 0 }
}

public struct DockerUsage: Sendable, Equatable {
    public var rows: [DockerUsageRow] = []
    public var images: [DockerImage] = []
    public var containers: [DockerContainer] = []
    public var volumes: [DockerVolume] = []

    public init(rows: [DockerUsageRow] = [], images: [DockerImage] = [], containers: [DockerContainer] = [], volumes: [DockerVolume] = []) {
        self.rows = rows
        self.images = images
        self.containers = containers
        self.volumes = volumes
    }

    public var totalSize: UInt64 { rows.reduce(0) { $0 + $1.size } }
    public var totalReclaimable: UInt64 { rows.reduce(0) { $0 + $1.reclaimable } }
    public func row(_ kind: DockerResourceKind) -> DockerUsageRow? { rows.first { $0.kind == kind } }
    public var danglingImages: [DockerImage] { images.filter(\.isDangling) }
}

public enum DockerParser {
    /// Parses `docker system df --format json`, which prints one JSON object per line.
    /// Older CLIs print a single JSON array; both are accepted.
    public static func parseSummary(_ output: String) -> [DockerUsageRow] {
        jsonObjects(output).compactMap { object in
            guard let kind = DockerResourceKind.from(string(object["Type"])) else { return nil }
            return DockerUsageRow(kind: kind, total: int(object["TotalCount"]), active: int(object["Active"]),
                                  size: size(object["Size"]), reclaimable: size(object["Reclaimable"]))
        }
        .sorted { lhs, rhs in
            DockerResourceKind.allCases.firstIndex(of: lhs.kind) ?? 0 < DockerResourceKind.allCases.firstIndex(of: rhs.kind) ?? 0
        }
    }

    /// Parses `docker system df -v --format json`: one object holding Images, Containers and Volumes arrays.
    public static func parseVerbose(_ output: String) -> (images: [DockerImage], containers: [DockerContainer], volumes: [DockerVolume]) {
        guard let root = jsonObjects(output).first else { return ([], [], []) }
        let images = array(root["Images"]).map { item in
            DockerImage(id: string(item["ID"]), repository: string(item["Repository"]), tag: string(item["Tag"]),
                        size: size(item["Size"]), containers: int(item["Containers"]), created: string(item["CreatedSince"]))
        }
        let containers = array(root["Containers"]).map { item in
            DockerContainer(id: string(item["ID"]), name: string(item["Names"]), image: string(item["Image"]),
                            state: string(item["State"]), status: string(item["Status"]), size: size(item["Size"]))
        }
        let volumes = array(root["Volumes"]).map { item in
            DockerVolume(name: string(item["Name"]), links: int(item["Links"]), size: size(item["Size"]))
        }
        return (images.sorted { $0.size > $1.size }, containers.sorted { $0.size > $1.size }, volumes.sorted { $0.size > $1.size })
    }

    /// True when stderr says the CLI exists but no daemon answered.
    public static func isDaemonDown(_ stderr: String) -> Bool {
        let text = stderr.lowercased()
        return text.contains("cannot connect to the docker daemon") || text.contains("is the docker daemon running")
            || text.contains("connection refused") || text.contains("no such file or directory")
    }

    static func jsonObjects(_ output: String) -> [[String: Any]] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) {
            if let object = value as? [String: Any] { return [object] }
            if let list = value as? [[String: Any]] { return list }
        }
        return trimmed.split(whereSeparator: \.isNewline).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
    }

    private static func array(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }

    private static func string(_ value: Any?) -> String {
        switch value {
        case let text as String: text
        case let number as NSNumber: number.stringValue
        default: ""
        }
    }

    private static func int(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber: number.intValue
        case let text as String: Int(text.trimmingCharacters(in: .whitespaces)) ?? 0
        default: 0
        }
    }

    private static func size(_ value: Any?) -> UInt64 {
        switch value {
        case let number as NSNumber: number.uint64Value
        case let text as String: HumanSize.parse(text) ?? 0
        default: 0
        }
    }
}
