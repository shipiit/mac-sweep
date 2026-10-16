import AppKit
import Foundation
import MacSweepCore
import Observation

@MainActor
@Observable
final class PrivacyPermissionsModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        /// Neither database could be opened; only Full Disk Access unlocks TCC.
        case needsFullDiskAccess
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var entries: [TCCEntry] = []
    private(set) var clients: [TCCEntry.Client: TCCClientInfo] = [:]
    private(set) var flags: [String: TCCRiskFlag] = [:]
    /// The user database opened but the system one didn't, so some grants are missing.
    private(set) var isPartial = false
    var showsAppleClients = false

    var groups: [TCCServiceGroup] {
        TCCRisk.group(showsAppleClients ? entries : entries.filter { !TCCRisk.isAppleSystemClient($0.client) })
    }

    var powerfulClientCount: Int {
        Set(entries.filter { $0.authorization.isGranted && $0.service.isPowerful && !TCCRisk.isAppleSystemClient($0.client) }.map(\.client)).count
    }

    var riskyClientCount: Int {
        Set(entries.filter { flags[$0.id] != nil }.map(\.client)).count
    }

    var grantedCount: Int { entries.filter(\.authorization.isGranted).count }

    func info(for client: TCCEntry.Client) -> TCCClientInfo {
        clients[client] ?? TCCClientInfo.unresolved(client)
    }

    func load() async {
        phase = .loading
        async let user = TCCReader.read(.user)
        async let system = TCCReader.read(.system)
        let results = [await user, await system]
        let isReadable = results.contains { if case .entries = $0 { true } else { false } }
        guard isReadable else {
            entries = []
            phase = results.contains(.needsFullDiskAccess) ? .needsFullDiskAccess : .failed(Self.failureMessage(results))
            return
        }
        let loaded = results.flatMap(\.entries)
        isPartial = results.contains { $0 != .entries($0.entries) }
        let resolved = await Task.detached(priority: .userInitiated) {
            Self.resolve(Set(loaded.map(\.client)))
        }.value
        entries = loaded
        clients = resolved
        flags = Dictionary(loaded.compactMap { entry in
            TCCRisk.assess(entry, client: resolved[entry.client] ?? .unresolved(entry.client)).map { (entry.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        phase = .loaded
    }

    private static func failureMessage(_ results: [TCCReadResult]) -> String {
        for result in results { if case .failed(let message) = result { return message } }
        return "The privacy database couldn't be read."
    }

    nonisolated static func resolve(_ clients: Set<TCCEntry.Client>) -> [TCCEntry.Client: TCCClientInfo] {
        var result: [TCCEntry.Client: TCCClientInfo] = [:]
        for client in clients { result[client] = resolve(client) }
        return result
    }

    nonisolated static func resolve(_ client: TCCEntry.Client) -> TCCClientInfo {
        switch client {
        case .bundleID(let id):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return .unresolved(client) }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return TCCClientInfo(name: name, path: url.path, signature: CodeSignature.check(path: url.path))
        case .path(let path):
            let bundle = path.range(of: ".app/").map { String(path[..<$0.lowerBound]) + ".app" }
            let shown = bundle ?? path
            return TCCClientInfo(name: (shown as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: ""),
                                 path: shown, signature: CodeSignature.check(path: path))
        }
    }
}
