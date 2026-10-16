import Foundation
import Testing
@testable import MacSweepCore

@Suite struct BrewCleanupParserTests {
    @Test func parsesFooterAndCountsItems() {
        let output = """
        Would remove: /Users/me/Library/Caches/Homebrew/node--22.1.0.bottle.tar.gz (20.1MB)
        Would remove (empty directory): /opt/homebrew/lib/gio
        Would remove: /opt/homebrew/Library/Homebrew/vendor/portable-ruby/4.0.2_1 (1,705 files, 34.6MB)
        ==> This operation would free approximately 2.2GB of disk space.
        """
        #expect(BrewParser.parseCleanup(output) == BrewCleanupPreview(reclaimable: 2_200_000_000, itemCount: 3))
    }

    @Test func noFooterMeansNothingToFree() {
        #expect(BrewParser.parseCleanup("") == .empty)
        #expect(BrewParser.parseCleanup("==> Downloading Homebrew API data\n") == .empty)
    }

    @Test func garbageFooterKeepsZero() {
        #expect(BrewParser.parseCleanup("would free approximately lots of disk space").reclaimable == 0)
        #expect(BrewParser.parseCleanup(" of disk space free approximately 1GB").reclaimable == 0)
    }

    @Test func snapshotSplitsFormulaeAndCasks() {
        let outdated = Updater.parseBrewOutdated("""
        {"formulae":[{"name":"node","installed_versions":["22.1.0"],"current_version":"22.2.0"}],
         "casks":[{"name":"firefox","installed_versions":"120","current_version":"121"}]}
        """)
        let snapshot = BrewSnapshot(outdated: outdated, cleanup: .empty)
        #expect(snapshot.outdatedFormulae.map(\.name) == ["node"])
        #expect(snapshot.outdatedCasks.map(\.name) == ["firefox"])
    }
}

@Suite struct DevServiceParserTests {
    let brewJSON = """
    [
      {"name":"redis","status":"started","user":"me","file":"/Users/me/Library/LaunchAgents/sh.brew.redis.plist","exit_code":null},
      {"name":"postgresql@16","status":"none","user":null,"file":"/opt/homebrew/opt/postgresql@16/sh.brew.postgresql@16.plist","exit_code":null},
      {"name":"mysql","status":"error","user":"me","file":"/x.plist","exit_code":1},
      {"name":"nginx","status":"started","user":"root","file":"/Library/LaunchDaemons/homebrew.mxcl.nginx.plist","exit_code":0},
      {"name":"odd","status":"other","user":"me","file":"/y.plist","exit_code":78},
      {"status":"started"}
    ]
    """

    @Test func parsesBrewServices() {
        let services = DevServiceParser.parseBrewServices(brewJSON, currentUser: "me")
        #expect(services.map(\.name) == ["mysql", "nginx", "odd", "postgresql@16", "redis"])
        let byName = Dictionary(uniqueKeysWithValues: services.map { ($0.name, $0) })
        #expect(byName["redis"]?.state == .running)
        #expect(byName["postgresql@16"]?.state == .stopped && byName["postgresql@16"]?.isUserDomain == true)
        #expect(byName["mysql"]?.state == .error && byName["mysql"]?.exitCode == 1)
        #expect(byName["nginx"]?.isUserDomain == false)
        #expect(byName["odd"]?.state == .error)
        #expect(services.allSatisfy { $0.source == .homebrew })
    }

    @Test func brewServicesGarbage() {
        #expect(DevServiceParser.parseBrewServices("", currentUser: "me").isEmpty)
        #expect(DevServiceParser.parseBrewServices("{}", currentUser: "me").isEmpty)
        #expect(DevServiceParser.parseBrewServices("Error: no services", currentUser: "me").isEmpty)
    }

    @Test func stateMapping() {
        #expect(DevServiceState.fromBrew("scheduled", exitCode: nil) == .scheduled)
        #expect(DevServiceState.fromBrew("STOPPED", exitCode: nil) == .stopped)
        #expect(DevServiceState.fromBrew("weird", exitCode: nil) == .unknown)
        #expect(DevServiceState.fromBrew("weird", exitCode: 0) == .unknown)
    }

    @Test func classifiesDevAgents() {
        #expect(DevServiceParser.isDevService(label: "com.me.postgres", executable: nil))
        #expect(DevServiceParser.isDevService(label: "local.db", executable: "/usr/local/bin/redis-server"))
        #expect(!DevServiceParser.isDevService(label: "homebrew.mxcl.redis", executable: "/opt/homebrew/bin/redis-server"))
        #expect(!DevServiceParser.isDevService(label: "sh.brew.postgresql@14", executable: nil))
        #expect(!DevServiceParser.isDevService(label: "com.google.GoogleUpdater.wake", executable: "/x/GoogleUpdater"))
        #expect(!DevServiceParser.isDevService(label: "", executable: nil))
    }

    @Test func launchdServicesUseStatus() {
        func item(_ label: String, scope: LaunchScope = .userAgent) -> LaunchItem {
            LaunchItem(label: label, plistPath: "/p/\(label).plist", scope: scope, program: nil, arguments: [],
                       runAtLoad: true, keepAlive: false, disabledInPlist: false, startInterval: nil)
        }
        let items = [item("com.me.redis"), item("com.me.mongod"), item("com.me.mysql"), item("com.me.minio", scope: .globalAgent),
                     item("homebrew.mxcl.kafka"), item("com.apple.notes")]
        let statuses = ["com.me.redis": LaunchStatus(pid: 42, lastExitStatus: 0), "com.me.mongod": LaunchStatus(pid: nil, lastExitStatus: 1)]
        let services = DevServiceParser.launchdServices(items, statuses: statuses)
        #expect(services.map(\.name) == ["com.me.redis", "com.me.mongod", "com.me.mysql"])
        #expect(services.map(\.state) == [.running, .error, .stopped])
        #expect(services[0].pid == 42 && services[0].source == .launchd)
        #expect(DevServiceParser.launchdServices([], statuses: [:]).isEmpty)
    }

    @Test func logPathsFromPlist() throws {
        let plist: [String: Any] = ["Label": "x", "StandardOutPath": "/var/log/x.log", "StandardErrorPath": "/var/log/x.err"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        #expect(DevServiceParser.logPaths(plist: data) == ["/var/log/x.err", "/var/log/x.log"])
        let same = try PropertyListSerialization.data(fromPropertyList: ["StandardOutPath": "/l", "StandardErrorPath": "/l"], format: .xml, options: 0)
        #expect(DevServiceParser.logPaths(plist: same) == ["/l"])
        let relative = try PropertyListSerialization.data(fromPropertyList: ["StandardOutPath": "x.log"], format: .xml, options: 0)
        #expect(DevServiceParser.logPaths(plist: relative).isEmpty)
        #expect(DevServiceParser.logPaths(plist: Data("garbage".utf8)).isEmpty)
        #expect(DevServiceParser.logPaths(plist: Data()).isEmpty)
    }
}

@Suite struct DevServiceCommandTests {
    @Test func brewCommands() throws {
        #expect(try DevServiceCommands.brew(.start, name: "redis") == ["services", "start", "redis"])
        #expect(try DevServiceCommands.brew(.restart, name: "postgresql@16") == ["services", "restart", "postgresql@16"])
        #expect(throws: DevCommandError.self) { try DevServiceCommands.brew(.stop, name: "--all") }
        #expect(throws: DevCommandError.self) { try DevServiceCommands.brew(.stop, name: "") }
    }

    @Test func launchctlCommands() throws {
        let plist = "/Users/me/Library/LaunchAgents/com.me.redis.plist"
        #expect(try DevServiceCommands.launchctl(.start, label: "com.me.redis", plistPath: plist, uid: 501)
            == [["bootstrap", "gui/501", plist], ["kickstart", "gui/501/com.me.redis"]])
        #expect(try DevServiceCommands.launchctl(.stop, label: "com.me.redis", plistPath: plist, uid: 501) == [["bootout", "gui/501", plist]])
        #expect(try DevServiceCommands.launchctl(.restart, label: "com.me.redis", plistPath: plist, uid: 501)
            == [["kickstart", "-k", "gui/501/com.me.redis"]])
        #expect(throws: DevCommandError.self) { try DevServiceCommands.launchctl(.stop, label: "a b", plistPath: plist, uid: 501) }
        #expect(throws: DevCommandError.self) { try DevServiceCommands.launchctl(.stop, label: "ok", plistPath: "rel.plist", uid: 501) }
        #expect(throws: DevCommandError.self) { try DevServiceCommands.launchctl(.stop, label: "ok", plistPath: "/x.txt", uid: 501) }
    }

    @Test func rootServicesRefuseActions() async {
        let service = DevService(name: "nginx", source: .homebrew, state: .running, plistPath: nil, isUserDomain: false)
        await #expect(throws: DevCommandError.self) { try await DevServiceControl.perform(.stop, on: service) }
    }
}

@Suite struct LogTailTests {
    @Test func lastLines() {
        let data = Data("one\ntwo\n\nthree\r\nfour\n".utf8)
        #expect(LogTail.lastLines(data, count: 2) == ["three", "four"])
        #expect(LogTail.lastLines(data, count: 10) == ["one", "two", "three", "four"])
        #expect(LogTail.lastLines(data, count: 0).isEmpty)
        #expect(LogTail.lastLines(Data(), count: 5).isEmpty)
        #expect(LogTail.lastLines(data, count: 10, startsMidLine: true) == ["two", "three", "four"])
        #expect(LogTail.lastLines(Data([0xFF, 0x0A, 0x41]), count: 5).count == 2)
    }

    @Test func readsOnlyTheEndOfTempFile() throws {
        let dir = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/service.log"
        let text = (1...500).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
        #expect(LogTail.read(path: path, lines: 3) == ["line 498", "line 499", "line 500"])
        let small = LogTail.read(path: path, lines: 1000, maxBytes: 30)
        #expect(small?.last == "line 500")
        #expect(small?.allSatisfy { $0.hasPrefix("line ") } == true)
        #expect(LogTail.read(path: dir + "/missing.log") == nil)
        try Data().write(to: URL(fileURLWithPath: dir + "/empty.log"))
        #expect(LogTail.read(path: dir + "/empty.log") == [])
    }
}
