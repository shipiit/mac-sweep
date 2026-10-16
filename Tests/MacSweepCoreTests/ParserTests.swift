import Foundation
import Testing
@testable import MacSweepCore

@Suite struct LsofParserTests {
    let sample = """
    p501
    cnode
    Lrahul
    f23
    PTCP
    n*:3000
    f24
    PTCP
    n[::]:3000
    p777
    cpostgres
    Lrahul
    f7
    PTCP
    n127.0.0.1:5432
    f8
    PTCP
    n[::1]:5432
    p900
    cmDNSResponder
    L_mdnsresponder
    f5
    PUDP
    n*:5353
    f6
    PUDP
    n*:*
    f9
    PUDP
    n192.168.1.2:5000->1.2.3.4:6000
    """

    @Test func parsesAndMergesDualStackSockets() {
        let ports = LsofParser.parse(sample)
        #expect(ports.map(\.port) == [3000, 5353, 5432])
        let node = ports[0]
        #expect(node.command == "node" && node.pid == 501 && node.user == "rahul" && node.proto == "TCP")
        #expect(node.addresses == ["*", "::"])
        #expect(!node.isLocalOnly)
    }

    @Test func loopbackOnlyIsLocal() {
        let postgres = LsofParser.parse(sample).first { $0.port == 5432 }
        #expect(postgres?.addresses == ["127.0.0.1", "::1"])
        #expect(postgres?.isLocalOnly == true)
    }

    @Test func skipsWildcardAndConnectedUdp() {
        let udp = LsofParser.parse(sample).filter { $0.proto == "UDP" }
        #expect(udp.map(\.port) == [5353])
    }

    @Test func emptyAndGarbageInput() {
        #expect(LsofParser.parse("").isEmpty)
        #expect(LsofParser.parse("garbage\n\nzzz").isEmpty)
        #expect(LsofParser.parse("n*:80").isEmpty)
    }

    @Test func endpointParsing() {
        #expect(LsofParser.parseEndpoint("[fe80::1%lo0]:631")?.port == 631)
        #expect(LsofParser.parseEndpoint("*:0") == nil)
        #expect(LsofParser.parseEndpoint("nocolon") == nil)
    }

    @Test func lsofArgumentsToggleUdp() {
        #expect(!PortScanner.lsofArguments(includeUDP: false).contains("-iUDP"))
        #expect(PortScanner.lsofArguments(includeUDP: true).contains("-iUDP"))
    }
}

@Suite struct LaunchParserTests {
    @Test func parsesLaunchctlList() {
        let output = "PID\tStatus\tLabel\n123\t0\tcom.example.agent\n-\t78\tcom.example.failed\nbad line\n"
        let statuses = LaunchctlParser.parseList(output)
        #expect(statuses["com.example.agent"] == LaunchStatus(pid: 123, lastExitStatus: 0))
        #expect(statuses["com.example.failed"] == LaunchStatus(pid: nil, lastExitStatus: 78))
        #expect(statuses.count == 2)
    }

    @Test func parsesDisabledInBothFormats() {
        let output = """
        disabled services = {
            "com.a" => disabled
            "com.b" => enabled
            "com.c" => true
            "com.d" => false
        }
        """
        #expect(LaunchctlParser.parseDisabled(output) == ["com.a", "com.c"])
        #expect(LaunchctlParser.parseDisabled("").isEmpty)
    }

    @Test func parsesPlistVariants() throws {
        let plist: [String: Any] = [
            "Label": "com.example.thing", "ProgramArguments": ["/usr/local/bin/thing", "--serve"],
            "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false], "StartInterval": 3600,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let item = try #require(LaunchItemScanner.parse(data, path: "/Library/LaunchAgents/x.plist", scope: .globalAgent))
        #expect(item.label == "com.example.thing")
        #expect(item.executable == "/usr/local/bin/thing")
        #expect(item.runAtLoad && item.keepAlive)
        #expect(item.startInterval == 3600)
        #expect(!item.disabledInPlist)
    }

    @Test func plistWithoutLabelFallsBackToFileName() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["Program": "/bin/x"], format: .xml, options: 0)
        let item = try #require(LaunchItemScanner.parse(data, path: "/tmp/com.fallback.plist", scope: .userAgent))
        #expect(item.label == "com.fallback")
        #expect(!item.keepAlive && !item.runAtLoad)
    }

    @Test func invalidPlistIsSkipped() {
        #expect(LaunchItemScanner.parse(Data("not a plist".utf8), path: "/x.plist", scope: .daemon) == nil)
    }

    @Test func commandsUseCorrectDomain() {
        let agent = LaunchItem(label: "com.a", plistPath: "/u/a.plist", scope: .userAgent, program: nil, arguments: [],
                               runAtLoad: true, keepAlive: false, disabledInPlist: false, startInterval: nil)
        #expect(LaunchControl.commands(for: .stop, item: agent, uid: 501) == [["bootout", "gui/501", "/u/a.plist"]])
        let daemon = LaunchItem(label: "com.d", plistPath: "/Library/LaunchDaemons/d.plist", scope: .daemon, program: nil, arguments: [],
                                runAtLoad: true, keepAlive: false, disabledInPlist: false, startInterval: nil)
        #expect(LaunchControl.commands(for: .disable, item: daemon, uid: 501).first == ["disable", "system/com.d"])
        #expect(LaunchControl.commands(for: .enable, item: daemon, uid: 501).last == ["bootstrap", "system", "/Library/LaunchDaemons/d.plist"])
    }
}

@Suite struct AdminRunnerTests {
    @Test func escapesAppleScriptQuotes() {
        #expect(AdminRunner.appleScript(for: "echo \"hi\\\"") == "do shell script \"echo \\\"hi\\\\\\\"\" with administrator privileges")
    }

    @Test func rejectsUnsafeTokens() {
        #expect(AdminRunner.isSafeToken("com.example.agent"))
        #expect(AdminRunner.isSafeToken("/Library/LaunchDaemons/com.x.plist"))
        #expect(!AdminRunner.isSafeToken("x; rm -rf /"))
        #expect(!AdminRunner.isSafeToken("$(whoami)"))
        #expect(!AdminRunner.isSafeToken(""))
    }
}

@Suite struct PortDescriberTests {
    @Test func categorises() {
        #expect(PortDescriber.category(command: "postgres", executable: "/opt/homebrew/bin/postgres") == .database)
        #expect(PortDescriber.category(command: "redis-server", executable: nil) == .database)
        #expect(PortDescriber.category(command: "ControlCenter", executable: "/System/Library/CoreServices/ControlCenter.app/x") == .system)
        #expect(PortDescriber.category(command: "node", executable: "/Users/x/.nvm/versions/node/v22/bin/node") == .devServer)
        #expect(PortDescriber.category(command: "OpenUsage", executable: "/Applications/OpenUsage.app/Contents/MacOS/OpenUsage") == .app)
        #expect(PortDescriber.category(command: "mystery", executable: "/usr/local/bin/mystery") == .app)
    }

    @Test func summarisesCommands() {
        #expect(PortDescriber.summary(["node", "/Users/x/app/node_modules/.bin/next", "dev", "--port", "3000"]) == "next dev --port 3000")
        #expect(PortDescriber.summary(["/usr/bin/python3", "-m", "uvicorn", "main:app"]) == "uvicorn main:app")
        #expect(PortDescriber.summary(["python", "/Users/x/site/manage.py", "runserver"]) == "manage.py runserver")
        #expect(PortDescriber.summary(["/opt/homebrew/bin/redis-server", "127.0.0.1:6379"]) == "redis-server 127.0.0.1:6379")
        #expect(PortDescriber.summary([]) == nil)
        #expect(PortDescriber.summary(["node"]) == "node")
        let long = PortDescriber.summary(["node", "x"] + Array(repeating: "--flag", count: 30)) ?? ""
        #expect(long.count == 70 && long.hasSuffix("…"))
    }
}

@Suite struct LoginItemsTests {
    @Test func parsesSystemEventsList() {
        let output = "MacSweep\t/Applications/MacSweep.app\tfalse\nSlack\t/Applications/Slack.app\ttrue\n\nbroken line\n"
        let items = LoginItems.parseList(output)
        #expect(items.map(\.name) == ["MacSweep", "Slack"])
        #expect(items[1].hidden && !items[0].hidden)
        #expect(LoginItems.parseList("").isEmpty)
    }

    @Test func parsesBackgroundTaskDump() {
        let dump = """
        ========================
         Records for UID 501 : 1A2B
        ========================
         #1:
                         UUID: 1111
                         Name: Docker
               Developer Name: Docker Inc
                         Type: app (0x2)
                  Disposition: [enabled, allowed, visible, notified] (0xb)
                   Identifier: 2.com.docker.docker
                          URL: file:///Applications/Docker.app/
         #2:
                         Name: com.docker.vmnetd
               Developer Name: (null)
                         Type: legacy daemon (0x10010)
                  Disposition: [disabled, allowed, visible, notified] (0xa)
                   Identifier: com.docker.vmnetd
                          URL: (null)
        """
        let items = LoginItems.parseDump(dump)
        #expect(items.map(\.name) == ["Docker", "com.docker.vmnetd"])
        #expect(items[0].enabled && items[0].type == "app" && items[0].developer == "Docker Inc")
        #expect(!items[1].enabled && items[1].developer == nil && items[1].url == nil && items[1].type == "legacy daemon")
        #expect(LoginItems.parseDump("").isEmpty)
    }

    @Test func escapesAppleScriptStrings() {
        #expect(LoginItems.escape(#"My "App""#) == #"My \"App\""#)
    }
}
