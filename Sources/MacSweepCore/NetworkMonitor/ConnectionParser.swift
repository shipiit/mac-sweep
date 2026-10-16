import Foundation

public struct NetEndpoint: Sendable, Hashable {
    public let address: String
    public let port: Int

    public init(address: String, port: Int) {
        self.address = address
        self.port = port
    }

    public var display: String { address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)" }
}

public struct NetConnection: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case listening
        case established
        /// Connecting, closing, or a UDP socket with no TCP state.
        case other
    }

    public let pid: Int32
    public let command: String
    public let proto: String
    public let local: NetEndpoint?
    public let remote: NetEndpoint?
    public let state: String?

    public var id: String {
        "\(pid)|\(proto)|\(local?.display ?? "*")|\(remote?.display ?? "-")"
    }

    public var kind: Kind {
        switch state {
        case "LISTEN": .listening
        case "ESTABLISHED": .established
        default: .other
        }
    }

    /// Established with a host outside this Mac and its local network.
    public var isOutboundInternet: Bool {
        guard kind == .established, let remote else { return false }
        return !AddressScope.isLocal(remote.address)
    }

    public init(pid: Int32, command: String, proto: String, local: NetEndpoint?, remote: NetEndpoint?, state: String?) {
        self.pid = pid
        self.command = command
        self.proto = proto
        self.local = local
        self.remote = remote
        self.state = state
    }
}

/// Parses `lsof -i -n -P -F pcPnT`: one field per line, `p` starts a process, `f` a socket.
public enum ConnectionParser {
    public static let arguments = ["-i", "-n", "-P", "-F", "pcPnT"]

    public static func parse(_ output: String) -> [NetConnection] {
        var connections: [NetConnection] = []
        var seen = Set<String>()
        var pid: Int32 = 0
        var command = ""
        var proto = ""
        var name: String?
        var state: String?

        func flush() {
            defer { name = nil; state = nil; proto = "" }
            guard pid > 0, let name, let connection = connection(pid: pid, command: command, proto: proto, name: name, state: state),
                  seen.insert(connection.id).inserted
            else { return }
            connections.append(connection)
        }

        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                flush()
                pid = Int32(value) ?? 0
                command = ""
            case "c": command = value
            case "f": flush()
            case "P": proto = value
            case "n": name = value
            case "T":
                if value.hasPrefix("ST=") { state = String(value.dropFirst(3)) }
            default: continue
            }
        }
        flush()
        return connections
    }

    static func connection(pid: Int32, command: String, proto: String, name: String, state: String?) -> NetConnection? {
        let parts = name.components(separatedBy: "->")
        guard let localText = parts.first, parts.count <= 2 else { return nil }
        let local = endpoint(localText)
        let remote = parts.count == 2 ? endpoint(parts[1]) : nil
        guard local != nil || remote != nil else { return nil }
        return NetConnection(pid: pid, command: command, proto: proto.isEmpty ? "TCP" : proto, local: local, remote: remote, state: state)
    }

    /// Accepts `1.2.3.4:443`, `[fe80::1]:22`, `*:5353`. A `*` port (unbound UDP) yields nil.
    static func endpoint(_ text: String) -> NetEndpoint? {
        guard let colon = text.lastIndex(of: ":"), let port = Int(text[text.index(after: colon)...]), port >= 0 else { return nil }
        var address = String(text[..<colon])
        if address.hasPrefix("["), address.hasSuffix("]") { address = String(address.dropFirst().dropLast()) }
        guard !address.isEmpty else { return nil }
        return NetEndpoint(address: address, port: port)
    }
}

public enum AddressScope {
    /// Loopback, private, link-local, CGNAT, multicast and wildcard addresses never leave the local network.
    public static func isLocal(_ address: String) -> Bool {
        let lower = address.lowercased()
        if lower == "*" || lower == "localhost" || lower == "::" || lower == "::1" || lower == "0.0.0.0" { return true }
        if lower.contains(":") {
            let mapped = lower.hasPrefix("::ffff:") ? String(lower.dropFirst(7)) : nil
            if let mapped, !mapped.contains(":") { return isLocal(mapped) }
            return lower.hasPrefix("fe80") || lower.hasPrefix("fc") || lower.hasPrefix("fd") || lower.hasPrefix("ff")
        }
        let octets = lower.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (0, _): return true
        case (172, 16...31), (192, 168), (169, 254), (100, 64...127): return true
        case (224...255, _): return true
        default: return false
        }
    }
}
