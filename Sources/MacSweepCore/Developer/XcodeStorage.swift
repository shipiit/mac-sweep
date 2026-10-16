import Foundation
import os

public struct XcodeLocation: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let path: String
    public var size: UInt64?
    public var itemCount: Int

    public init(id: String, title: String, detail: String, path: String, size: UInt64? = nil, itemCount: Int = 0) {
        self.id = id
        self.title = title
        self.detail = detail
        self.path = path
        self.size = size
        self.itemCount = itemCount
    }
}

public struct Simulator: Sendable, Equatable, Identifiable {
    public let udid: String
    public let name: String
    public let runtime: String
    public let state: String
    public let isAvailable: Bool
    public let dataSize: UInt64
    public let lastBooted: Date?

    public var id: String { udid }
    public var isBooted: Bool { state == "Booted" }
}

public enum XcodeStorage {
    private static let log = Logger(subsystem: Log.subsystem, category: "xcode")

    public static func locations(home: String) -> [XcodeLocation] {
        let developer = home + "/Library/Developer"
        return [
            XcodeLocation(id: "derived", title: "DerivedData", detail: "Build products and indexes; Xcode rebuilds them.",
                          path: developer + "/Xcode/DerivedData"),
            XcodeLocation(id: "archives", title: "Archives", detail: "App Store and ad-hoc builds. Keep ones you may need to symbolicate.",
                          path: developer + "/Xcode/Archives"),
            XcodeLocation(id: "ios-support", title: "iOS DeviceSupport", detail: "Symbols copied from each iOS version you debugged on.",
                          path: developer + "/Xcode/iOS DeviceSupport"),
            XcodeLocation(id: "watch-support", title: "watchOS DeviceSupport", detail: "Symbols for paired Apple Watch debugging.",
                          path: developer + "/Xcode/watchOS DeviceSupport"),
            XcodeLocation(id: "sim-caches", title: "Simulator caches", detail: "Dyld and runtime caches; recreated on demand.",
                          path: developer + "/CoreSimulator/Caches"),
        ]
    }

    /// Children of a location, which is what actually gets trashed; the location folder itself stays.
    public static func children(of path: String, fileManager: FileManager = .default) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: path)) ?? []).filter { !$0.hasPrefix(".") }.sorted().map { path + "/" + $0 }
    }

    /// Parses `xcrun simctl list -j devices`.
    public static func parseSimulators(_ json: String) -> [Simulator] {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let devices = root["devices"] as? [String: Any]
        else { return [] }
        let dateFormatter = ISO8601DateFormatter()
        return devices.flatMap { runtime, value -> [Simulator] in
            (value as? [[String: Any]] ?? []).compactMap { device in
                guard let udid = device["udid"] as? String, let name = device["name"] as? String else { return nil }
                return Simulator(udid: udid, name: name, runtime: runtimeName(runtime), state: device["state"] as? String ?? "",
                                 isAvailable: device["isAvailable"] as? Bool ?? true,
                                 dataSize: (device["dataPathSize"] as? NSNumber)?.uint64Value ?? 0,
                                 lastBooted: (device["lastBootedAt"] as? String).flatMap(dateFormatter.date(from:)))
            }
        }
        .sorted { ($0.runtime, $0.name) < ($1.runtime, $1.name) }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-5" → "iOS 26.5".
    public static func runtimeName(_ identifier: String) -> String {
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        let parts = last.split(separator: "-")
        guard let platform = parts.first, parts.count > 1 else { return last }
        return "\(platform) " + parts.dropFirst().joined(separator: ".")
    }

    public static func simulators() async throws -> [Simulator] {
        let result = try await DevShell.run("/usr/bin/xcrun", ["simctl", "list", "-j", "devices"], timeout: 60, tool: "Xcode")
        guard result.status == 0 else { throw DevCommandError.notInstalled("Xcode") }
        return parseSimulators(result.stdout)
    }

    public static func deleteUnavailableSimulators() async throws {
        log.info("deleting unavailable simulators")
        let result = try await DevShell.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"], timeout: 300, tool: "Xcode")
        guard result.status == 0 else { throw DevCommandError.failed(DockerClient.firstLine(result.stderr)) }
    }
}
