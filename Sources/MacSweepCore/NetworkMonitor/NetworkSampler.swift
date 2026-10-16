import Darwin
import Foundation

public struct NetworkSample: Sendable, Equatable {
    public let activity: [AppNetworkActivity]
    /// nettop failed or printed nothing usable; connections are still shown, just without byte counts.
    public let hasTraffic: Bool
    public let date: Date
}

/// Bounded, async reverse-DNS cache. Only public addresses are looked up, a few at a time, and failures
/// are cached too so a host without a PTR record isn't asked again every sample.
public actor ReverseDNSCache {
    public typealias Resolver = @Sendable (String) async -> String?

    private var names: [String: String?] = [:]
    private var order: [String] = []
    private var inFlight: Set<String> = []
    private let capacity: Int
    private let limiter: AsyncLimiter
    private let resolver: Resolver

    public init(capacity: Int = 512, concurrency: Int = 3, resolver: @escaping Resolver = ReverseDNSCache.systemLookup) {
        self.capacity = max(capacity, 1)
        self.limiter = AsyncLimiter(limit: concurrency)
        self.resolver = resolver
    }

    /// The cached hostname, or nil when unknown, not yet resolved, or not looked up.
    public func cachedName(for address: String) -> String? {
        names[address] ?? nil
    }

    /// Resolves addresses not seen before and returns every known name among them.
    public func resolve(_ addresses: [String]) async -> [String: String] {
        let pending = Set(addresses).filter { !AddressScope.isLocal($0) && names[$0] == nil && !inFlight.contains($0) }
        inFlight.formUnion(pending)
        await withTaskGroup(of: (String, String?).self) { group in
            for address in pending {
                group.addTask { [limiter, resolver] in
                    await limiter.acquire()
                    let name = await resolver(address)
                    await limiter.release()
                    return (address, name)
                }
            }
            for await (address, name) in group { store(address, name) }
        }
        var result: [String: String] = [:]
        for address in addresses { if let name = names[address] ?? nil { result[address] = name } }
        return result
    }

    private func store(_ address: String, _ name: String?) {
        inFlight.remove(address)
        if names[address] == nil { order.append(address) }
        names[address] = .some(name)
        while order.count > capacity { names.removeValue(forKey: order.removeFirst()) }
    }

    /// `getnameinfo` blocks, so it runs on a Dispatch queue rather than the cooperative pool.
    public static let systemLookup: Resolver = { address in
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: blockingLookup(address)) }
        }
    }

    static func blockingLookup(_ address: String) -> String? {
        var hints = addrinfo()
        hints.ai_flags = AI_NUMERICHOST
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(address, nil, &hints, &info) == 0, let first = info else { return nil }
        defer { freeaddrinfo(info) }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(first.pointee.ai_addr, first.pointee.ai_addrlen, &host, socklen_t(host.count), nil, 0, NI_NAMEREQD) == 0
        else { return nil }
        let name = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty || name == address ? nil : name
    }
}

/// Caches code-signature verdicts per executable path; checking a signature costs milliseconds.
public actor SignatureCache {
    private var verdicts: [String: SignatureStatus] = [:]
    private let check: @Sendable (String) -> SignatureStatus

    public init(check: @escaping @Sendable (String) -> SignatureStatus = { CodeSignature.check(path: $0) }) {
        self.check = check
    }

    public func status(for path: String) -> SignatureStatus {
        if let cached = verdicts[path] { return cached }
        let status = check(path)
        if verdicts.count > 2_000 { verdicts.removeAll() }
        verdicts[path] = status
        return status
    }
}

public enum NetworkSampler {
    /// Without root, lsof only lists this user's sockets; nettop sees traffic for every process.
    public static func sample(signatures: SignatureCache) async -> NetworkSample {
        async let lsof = try? Shell.run("/usr/sbin/lsof", ConnectionParser.arguments)
        async let nettop = try? Shell.run("/usr/bin/nettop", NettopParser.arguments)
        let connections = ConnectionParser.parse(await lsof?.stdout ?? "")
        let traffic = NettopParser.parse(await nettop?.stdout ?? "")
        var identities: [Int32: ProcessIdentity] = [:]
        for pid in Set(connections.map(\.pid)) {
            let path = ProcReader.executablePath(pid)
            let signature: SignatureStatus? = if let path { await signatures.status(for: path) } else { nil }
            identities[pid] = ProcessIdentity(path: path, signature: signature)
        }
        return NetworkSample(activity: ConnectionRisk.aggregate(connections: connections, traffic: traffic, identities: identities),
                             hasTraffic: !traffic.isEmpty, date: Date())
    }
}
