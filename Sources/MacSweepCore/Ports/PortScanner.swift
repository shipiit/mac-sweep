import Foundation

public struct ListeningPort: Identifiable, Hashable, Sendable {
    public let pid: Int32
    public let command: String
    public let user: String
    public let proto: String
    public let port: Int
    public let addresses: [String]

    public var id: String { "\(proto)-\(pid)-\(port)" }

    /// True when every bound address is loopback, i.e. unreachable from the network.
    public var isLocalOnly: Bool {
        addresses.allSatisfy { $0 == "127.0.0.1" || $0 == "::1" || $0.hasPrefix("127.") || $0 == "localhost" }
    }

    public init(pid: Int32, command: String, user: String, proto: String, port: Int, addresses: [String]) {
        self.pid = pid
        self.command = command
        self.user = user
        self.proto = proto
        self.port = port
        self.addresses = addresses
    }
}

public enum PortScanner {
    public static func lsofArguments(includeUDP: Bool) -> [String] {
        var arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]
        if includeUDP { arguments.append("-iUDP") }
        return arguments + ["-FpcLPn"]
    }

    /// Without root, lsof only reports sockets owned by the current user.
    public static func scan(includeUDP: Bool) async throws -> [ListeningPort] {
        let result = try await Shell.run("/usr/sbin/lsof", lsofArguments(includeUDP: includeUDP))
        // lsof exits 1 when nothing matches; that's an empty list, not an error.
        return LsofParser.parse(result.stdout)
    }

    public static func scanAsAdmin(includeUDP: Bool) async throws -> [ListeningPort] {
        LsofParser.parse(try await AdminRunner.listeningPorts(includeUDP: includeUDP))
    }
}

/// Parses `lsof -F pcLPn` field output: one field per line, prefixed by its identifier character.
public enum LsofParser {
    public static func parse(_ output: String) -> [ListeningPort] {
        struct Key: Hashable { let pid: Int32; let proto: String; let port: Int }
        var merged: [Key: (command: String, user: String, addresses: [String])] = [:]
        var order: [Key] = []

        var pid: Int32 = 0
        var command = ""
        var user = ""
        var proto = ""

        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value) ?? 0
                command = ""
                user = ""
            case "c": command = value
            case "L": user = value
            case "f": proto = ""
            case "P": proto = value
            case "n":
                guard pid > 0, let endpoint = parseEndpoint(value) else { continue }
                let key = Key(pid: pid, proto: proto.isEmpty ? "TCP" : proto, port: endpoint.port)
                if var existing = merged[key] {
                    if !existing.addresses.contains(endpoint.address) { existing.addresses.append(endpoint.address) }
                    merged[key] = existing
                } else {
                    merged[key] = (command, user, [endpoint.address])
                    order.append(key)
                }
            default: continue
            }
        }

        return order.compactMap { key in
            merged[key].map {
                ListeningPort(pid: key.pid, command: $0.command, user: $0.user, proto: key.proto, port: key.port, addresses: $0.addresses)
            }
        }
        .sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    /// Accepts `*:3000`, `127.0.0.1:5432`, `[::1]:8080`; skips connected UDP (`a->b`) and wildcard ports.
    static func parseEndpoint(_ name: String) -> (address: String, port: Int)? {
        guard !name.contains("->"), let colon = name.lastIndex(of: ":") else { return nil }
        guard let port = Int(name[name.index(after: colon)...]), port > 0 else { return nil }
        var address = String(name[..<colon])
        if address.hasPrefix("["), address.hasSuffix("]") { address = String(address.dropFirst().dropLast()) }
        return (address, port)
    }
}
