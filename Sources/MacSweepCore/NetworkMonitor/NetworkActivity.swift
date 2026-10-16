import Foundation

public struct NetRiskFlag: Sendable, Equatable {
    public let severity: FindingSeverity
    public let reason: String
}

/// One process's sockets, traffic counters and trust verdict in a sample.
public struct AppNetworkActivity: Identifiable, Sendable, Equatable {
    public let pid: Int32
    public let name: String
    public let path: String?
    public let signature: SignatureStatus?
    public let connections: [NetConnection]
    public let traffic: ProcessTraffic?
    public let flag: NetRiskFlag?

    public var id: Int32 { pid }
    public var establishedCount: Int { connections.filter { $0.kind == .established }.count }
    public var listeningCount: Int { connections.filter { $0.kind == .listening }.count }
    public var outboundCount: Int { connections.filter(\.isOutboundInternet).count }
}

public struct ProcessIdentity: Sendable, Equatable {
    public let path: String?
    public let signature: SignatureStatus?

    public init(path: String?, signature: SignatureStatus?) {
        self.path = path
        self.signature = signature
    }
}

public enum ConnectionRisk {
    /// Flags untrusted code reaching the internet. Listening sockets and LAN traffic are ignored, and a
    /// process whose path can't be read (another user's, or already exited) is never guessed at.
    public static func assess(path: String?, signature: SignatureStatus?, connections: [NetConnection]) -> NetRiskFlag? {
        guard connections.contains(where: \.isOutboundInternet), let path else { return nil }
        if let place = SecurityAudit.suspiciousLocations.first(where: path.lowercased().contains) {
            return NetRiskFlag(severity: .high, reason: "Connecting out from a temporary or shared folder (\(place.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))")
        }
        switch signature {
        case .unsigned?, .invalid?:
            return NetRiskFlag(severity: .high, reason: "Unsigned or tampered program connecting to the internet")
        case .adHoc?:
            return NetRiskFlag(severity: .low, reason: "No identified developer (common for Homebrew and dev tools)")
        default:
            return nil
        }
    }

    public static func aggregate(connections: [NetConnection], traffic: [Int32: ProcessTraffic],
                                 identities: [Int32: ProcessIdentity]) -> [AppNetworkActivity] {
        Dictionary(grouping: connections, by: \.pid)
            .map { pid, sockets in
                let identity = identities[pid]
                let command = sockets.first?.command ?? ""
                let name = command.isEmpty ? (traffic[pid]?.name ?? "pid \(pid)") : command
                return AppNetworkActivity(
                    pid: pid, name: displayName(command: name, path: identity?.path), path: identity?.path, signature: identity?.signature,
                    connections: sockets.sorted { (rank($0.kind), $0.id) < (rank($1.kind), $1.id) },
                    traffic: traffic[pid],
                    flag: assess(path: identity?.path, signature: identity?.signature, connections: sockets)
                )
            }
            .sorted { lhs, rhs in
                let left = (-(lhs.flag?.severity.rawValue ?? -1), -lhs.outboundCount, -lhs.establishedCount, lhs.name)
                let right = (-(rhs.flag?.severity.rawValue ?? -1), -rhs.outboundCount, -rhs.establishedCount, rhs.name)
                return left < right
            }
    }

    /// lsof truncates command names; the bundle or binary name from the path is what users recognise.
    static func displayName(command: String, path: String?) -> String {
        guard let path else { return command }
        if let range = path.range(of: ".app/Contents/") {
            return ((String(path[..<range.lowerBound]) as NSString).lastPathComponent)
        }
        return (path as NSString).lastPathComponent
    }

    private static func rank(_ kind: NetConnection.Kind) -> Int {
        switch kind {
        case .established: 0
        case .listening: 1
        case .other: 2
        }
    }
}
