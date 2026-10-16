import Foundation
import Testing
@testable import MacSweepCore

@Suite struct ConnectionParserTests {
    static let lsof = """
        p628
        crapportd
        f10
        PTCP
        n[fe80:e::474:829:ab32:d63d]:50877->[fe80:e::1080:d78d:c64c:7a9]:63552
        TST=ESTABLISHED
        TQR=0
        TQS=0
        f12
        PTCP
        n*:50877
        TST=LISTEN
        f14
        PTCP
        n*:50877
        TST=LISTEN
        f24
        PUDP
        n*:*
        f25
        PUDP
        n*:5353
        p900
        cGoogle Chrome He
        f30
        PTCP
        n192.168.1.5:51000->142.250.74.78:443
        TST=ESTABLISHED
        f31
        PTCP
        n192.168.1.5:51001->142.250.74.79:443
        TST=SYN_SENT
        """

    @Test func parsesEstablishedListeningAndUDP() {
        let connections = ConnectionParser.parse(Self.lsof)
        #expect(connections.count == 5)
        let first = connections[0]
        #expect(first.pid == 628 && first.command == "rapportd")
        #expect(first.kind == .established)
        #expect(first.remote == NetEndpoint(address: "fe80:e::1080:d78d:c64c:7a9", port: 63552))
        #expect(!first.isOutboundInternet)
        #expect(connections[1].kind == .listening)
        #expect(connections[1].remote == nil)
        let udp = connections[2]
        #expect(udp.proto == "UDP" && udp.kind == .other && udp.local?.port == 5353)
        let chrome = connections[3]
        #expect(chrome.command == "Google Chrome He")
        #expect(chrome.isOutboundInternet)
        #expect(chrome.remote?.display == "142.250.74.78:443")
        #expect(connections[4].kind == .other)
        #expect(!connections[4].isOutboundInternet)
    }

    @Test func emptyAndGarbageInput() {
        #expect(ConnectionParser.parse("").isEmpty)
        #expect(ConnectionParser.parse("lsof: WARNING: can't stat()\n???\n").isEmpty)
        #expect(ConnectionParser.parse("n1.2.3.4:80->5.6.7.8:443\n").isEmpty)
        #expect(ConnectionParser.parse("pabc\nn1.2.3.4:80\n").isEmpty)
    }

    @Test func endpoints() {
        #expect(ConnectionParser.endpoint("[::1]:8080") == NetEndpoint(address: "::1", port: 8080))
        #expect(ConnectionParser.endpoint("*:22") == NetEndpoint(address: "*", port: 22))
        #expect(ConnectionParser.endpoint("*:*") == nil)
        #expect(ConnectionParser.endpoint(":80") == nil)
        #expect(ConnectionParser.endpoint("nohost") == nil)
        #expect(NetEndpoint(address: "::1", port: 1).display == "[::1]:1")
    }
}

@Suite struct AddressScopeTests {
    @Test(arguments: ["127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.1", "192.168.0.1", "169.254.1.1", "100.64.0.1",
                      "224.0.0.251", "255.255.255.255", "0.0.0.0", "::1", "fe80::1", "fd00::1", "ff02::fb", "*", "::ffff:192.168.1.1"])
    func localAddresses(_ address: String) {
        #expect(AddressScope.isLocal(address))
    }

    @Test(arguments: ["8.8.8.8", "172.32.0.1", "142.250.74.78", "2a00:1450:4001::200e", "::ffff:8.8.8.8", "100.128.0.1"])
    func publicAddresses(_ address: String) {
        #expect(!AddressScope.isLocal(address))
    }

    @Test func garbageIsNotLocal() {
        #expect(!AddressScope.isLocal("example.com"))
        #expect(!AddressScope.isLocal(""))
    }
}

@Suite struct NettopParserTests {
    @Test func parsesPerProcessBytes() {
        let output = """
            ,bytes_in,bytes_out,
            launchd.1,0,0,
            mDNSResponder.421,234866052,38653230,
            Weird, Name.v2.777,10,20,
            Helper.900,5,6,
            Helper.900,1,1,
            """
        let traffic = NettopParser.parse(output)
        #expect(traffic.count == 4)
        #expect(traffic[421] == ProcessTraffic(pid: 421, name: "mDNSResponder", bytesIn: 234_866_052, bytesOut: 38_653_230))
        #expect(traffic[777]?.name == "Weird, Name.v2")
        #expect(traffic[900]?.bytesIn == 6)
    }

    @Test func emptyAndGarbage() {
        #expect(NettopParser.parse("").isEmpty)
        #expect(NettopParser.parse(",bytes_in,bytes_out,\n").isEmpty)
        #expect(NettopParser.parse("nettop: permission denied\nnopid,1,2,\nx.0,1,2,\ny.5,a,b,").isEmpty)
    }
}

@Suite struct ConnectionRiskTests {
    let outbound = NetConnection(pid: 5, command: "agent", proto: "TCP", local: NetEndpoint(address: "192.168.1.2", port: 5000),
                                 remote: NetEndpoint(address: "8.8.8.8", port: 443), state: "ESTABLISHED")
    let listening = NetConnection(pid: 5, command: "agent", proto: "TCP", local: NetEndpoint(address: "*", port: 80), remote: nil, state: "LISTEN")

    @Test func flagsUntrustedOutbound() {
        #expect(ConnectionRisk.assess(path: "/opt/x/agent", signature: .unsigned, connections: [outbound])?.severity == .high)
        #expect(ConnectionRisk.assess(path: "/opt/x/agent", signature: .invalid, connections: [outbound])?.severity == .high)
        #expect(ConnectionRisk.assess(path: "/opt/homebrew/bin/curl", signature: .adHoc, connections: [outbound])?.severity == .low)
        let temp = ConnectionRisk.assess(path: "/private/tmp/agent", signature: .developer(teamID: "T"), connections: [outbound])
        #expect(temp?.severity == .high)
        #expect(temp?.reason.contains("tmp") == true)
    }

    @Test func ignoresTrustedListeningUnknownPath() {
        #expect(ConnectionRisk.assess(path: "/Applications/A.app/Contents/MacOS/A", signature: .apple, connections: [outbound]) == nil)
        #expect(ConnectionRisk.assess(path: "/opt/x", signature: .unsigned, connections: [listening]) == nil)
        #expect(ConnectionRisk.assess(path: nil, signature: nil, connections: [outbound]) == nil)
        #expect(ConnectionRisk.assess(path: "/opt/x", signature: .unsigned, connections: []) == nil)
    }

    @Test func aggregatesAndSortsFlaggedFirst() {
        let trusted = NetConnection(pid: 9, command: "Safari", proto: "TCP", local: nil, remote: NetEndpoint(address: "1.1.1.1", port: 443), state: "ESTABLISHED")
        let activity = ConnectionRisk.aggregate(
            connections: [trusted, listening, outbound],
            traffic: [5: ProcessTraffic(pid: 5, name: "agent", bytesIn: 10, bytesOut: 20)],
            identities: [5: ProcessIdentity(path: "/opt/x/agent", signature: .unsigned),
                         9: ProcessIdentity(path: "/Applications/Safari.app/Contents/MacOS/Safari", signature: .apple)]
        )
        #expect(activity.map(\.pid) == [5, 9])
        #expect(activity[0].flag?.severity == .high)
        #expect(activity[0].connections.first?.kind == .established)
        #expect(activity[0].establishedCount == 1 && activity[0].listeningCount == 1 && activity[0].outboundCount == 1)
        #expect(activity[0].traffic?.bytesOut == 20)
        #expect(activity[1].name == "Safari")
        #expect(activity[1].traffic == nil)
        #expect(ConnectionRisk.aggregate(connections: [], traffic: [:], identities: [:]).isEmpty)
    }

    @Test func namesFallBackToTrafficThenPid() {
        let nameless = NetConnection(pid: 3, command: "", proto: "TCP", local: nil, remote: nil, state: nil)
        #expect(ConnectionRisk.aggregate(connections: [nameless], traffic: [3: ProcessTraffic(pid: 3, name: "nt", bytesIn: 0, bytesOut: 0)],
                                         identities: [:]).first?.name == "nt")
        #expect(ConnectionRisk.aggregate(connections: [nameless], traffic: [:], identities: [:]).first?.name == "pid 3")
        #expect(ConnectionRisk.displayName(command: "x", path: "/Applications/Slack.app/Contents/Frameworks/H.app/Contents/MacOS/H") == "Slack")
        #expect(ConnectionRisk.displayName(command: "x", path: "/usr/bin/curl") == "curl")
    }
}

@Suite struct ReverseDNSCacheTests {
    @Test func resolvesOnlyPublicAddressesAndCachesResultsIncludingFailures() async {
        let calls = CallLog()
        let cache = ReverseDNSCache(capacity: 10, concurrency: 2) { address in
            calls.append(address)
            return address == "8.8.8.8" ? "dns.google" : nil
        }
        let first = await cache.resolve(["8.8.8.8", "9.9.9.9", "192.168.1.1", "127.0.0.1"])
        #expect(first == ["8.8.8.8": "dns.google"])
        #expect(Set(calls.get()) == ["8.8.8.8", "9.9.9.9"])
        _ = await cache.resolve(["8.8.8.8", "9.9.9.9"])
        #expect(calls.get().count == 2)
        #expect(await cache.cachedName(for: "8.8.8.8") == "dns.google")
        #expect(await cache.cachedName(for: "9.9.9.9") == nil)
        #expect(await cache.resolve([]).isEmpty)
    }

    @Test func evictsOldestBeyondCapacity() async {
        let cache = ReverseDNSCache(capacity: 2, concurrency: 1) { "host-\($0)" }
        _ = await cache.resolve(["1.1.1.1"])
        _ = await cache.resolve(["2.2.2.2"])
        _ = await cache.resolve(["3.3.3.3"])
        #expect(await cache.cachedName(for: "1.1.1.1") == nil)
        #expect(await cache.cachedName(for: "3.3.3.3") == "host-3.3.3.3")
    }

    @Test func signatureCacheChecksEachPathOnce() async {
        let calls = LockedBox(0)
        let cache = SignatureCache { _ in calls.set(calls.get() + 1); return .adHoc }
        #expect(await cache.status(for: "/a") == .adHoc)
        #expect(await cache.status(for: "/a") == .adHoc)
        #expect(calls.get() == 1)
    }
}

/// Records resolver calls atomically; lookups run concurrently.
private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) { lock.withLock { values.append(value) } }
    func get() -> [String] { lock.withLock { values } }
}
