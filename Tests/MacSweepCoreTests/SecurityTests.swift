import Foundation
import Testing
@testable import MacSweepCore

@Suite struct SecurityAuditTests {
    func item(_ label: String, program: String?, runAtLoad: Bool = true, scope: LaunchScope = .userAgent) -> LaunchItem {
        LaunchItem(label: label, plistPath: "/Users/test/Library/LaunchAgents/\(label).plist", scope: scope, program: program,
                   arguments: [], runAtLoad: runAtLoad, keepAlive: false, disabledInPlist: false, startInterval: nil)
    }

    @Test func trustedProgramsProduceNoFindings() {
        let findings = SecurityAudit.auditLaunchItems([item("com.google.keystone.agent", program: "/Library/Google/x")]) { _ in
            .developer(teamID: "EQHXZ8M8AV")
        }
        #expect(findings.isEmpty)
    }

    @Test func flagsAppleImpersonation() {
        let findings = SecurityAudit.auditLaunchItems([item("com.apple.updater", program: "/Users/test/Library/x/updater")]) { _ in .adHoc }
        #expect(findings.contains { $0.severity == .high && $0.title.contains("Pretends to be Apple") })
    }

    @Test func realAppleAgentIsFine() {
        #expect(SecurityAudit.auditLaunchItems([item("com.apple.something", program: "/usr/libexec/x")]) { _ in .apple }.isEmpty)
    }

    @Test func flagsTempLocationsHiddenFoldersAndAdware() {
        let findings = SecurityAudit.auditLaunchItems([
            item("com.x.tmp", program: "/private/tmp/payload"),
            item("com.x.hidden", program: "/Users/test/Library/Application Support/.hidden/agent"),
            item("com.mackeeper.helper", program: "/Applications/MacKeeper.app/Contents/MacOS/helper"),
        ]) { _ in .developer(teamID: "T") }
        #expect(findings.contains { $0.title == "Starts from a temporary folder" })
        #expect(findings.contains { $0.title == "Runs hidden program at login" })
        #expect(findings.contains { $0.title.hasPrefix("Known adware") })
    }

    @Test func unsignedAndMissingPrograms() {
        let unsigned = SecurityAudit.auditLaunchItems([item("com.x.a", program: "/opt/a")]) { _ in .unsigned }
        #expect(unsigned.first?.severity == .medium)
        let notAtLoad = SecurityAudit.auditLaunchItems([item("com.x.b", program: "/opt/b", runAtLoad: false)]) { _ in .invalid }
        #expect(notAtLoad.first?.severity == .low)
        let missing = SecurityAudit.auditLaunchItems([item("com.x.c", program: "/gone")]) { _ in .missing }
        #expect(missing.first?.title == "Leftover startup item")
    }

    @Test func itemWithoutProgramOnlyChecksName() {
        #expect(SecurityAudit.auditLaunchItems([item("com.x.none", program: nil)]) { _ in .unsigned }.isEmpty)
    }

    @Test func processAuditFlagsUntrustedTempBinariesOnly() {
        func snapshot(_ pid: Int32, _ path: String?) -> ProcessSnapshot {
            ProcessSnapshot(pid: pid, ppid: 1, name: "p\(pid)", path: path, uid: 501, user: "u", memory: nil, cpuTimeNanos: nil, threads: nil, started: nil)
        }
        let processes = [snapshot(1, "/private/tmp/x"), snapshot(5, "/private/tmp/x"), snapshot(2, "/Users/test/Downloads/tool"),
                         snapshot(3, "/Applications/A.app/Contents/MacOS/A"), snapshot(4, nil),
                         snapshot(6, "/Users/test/Library/Caches/ms-playwright/chrome-headless-shell")]
        let findings = SecurityAudit.auditProcesses(processes) { path in path.contains("Downloads") ? .developer(teamID: "T") : .unsigned }
        #expect(findings.count == 1)
        #expect(findings.first?.severity == .high)
        #expect(findings.first?.title.contains("2 processes") == true)
    }

    @Test func unsignedDownloadIsMedium() {
        let process = ProcessSnapshot(pid: 9, ppid: 1, name: "tool", path: "/Users/test/Downloads/tool", uid: 501, user: "u",
                                      memory: nil, cpuTimeNanos: nil, threads: nil, started: nil)
        #expect(SecurityAudit.auditProcesses([process]) { _ in .adHoc }.first?.severity == .medium)
    }

    @Test func realSignatureChecks() {
        #expect(CodeSignature.check(path: "/bin/ls") == .apple)
        #expect(CodeSignature.check(path: "/no/such/file") == .missing)
    }
}

@Suite struct ProtectionAndExtensionTests {
    @Test func parsesProtectionOutputs() {
        #expect(ProtectionStatus.parseSIP("System Integrity Protection status: enabled.") == .on)
        #expect(ProtectionStatus.parseSIP("System Integrity Protection status: disabled.") == .off)
        #expect(ProtectionStatus.parseSIP("") == .unknown)
        #expect(ProtectionStatus.parseGatekeeper("assessments enabled") == .on)
        #expect(ProtectionStatus.parseGatekeeper("assessments disabled") == .off)
        #expect(ProtectionStatus.parseFileVault("FileVault is On.") == .on)
        #expect(ProtectionStatus.parseFileVault("FileVault is Off.") == .off)
        #expect(ProtectionStatus.parseFirewall("Firewall is enabled. (State = 1)") == .on)
        #expect(ProtectionStatus.parseFirewall("Firewall is disabled. (State = 0)") == .off)
        #expect(ProtectionStatus.parseFirewall("") == .unknown)
    }

    @Test func parsesManifestsAndLocalisedNames() throws {
        let manifest = #"{"name":"__MSG_appName__","version":"1.2","permissions":["cookies","tabs"],"host_permissions":["<all_urls>"],"icons":{"16":"i16.png","128":"i128.png"},"update_url":"https://clients2.google.com/service/update2/crx"}"#
        let parsed = try #require(BrowserExtensions.parseManifest(Data(manifest.utf8), localeLookup: { $0 == "appName" ? "Grammar Pro" : nil }))
        #expect(parsed.name == "Grammar Pro")
        #expect(parsed.icon == "i128.png")
        #expect(parsed.fromStore)
        #expect(BrowserExtensions.parseManifest(Data("{}".utf8)) == nil)
    }

    func ext(_ permissions: [String], fromStore: Bool = true) -> BrowserExtension {
        BrowserExtension(browser: "Chrome", profile: "Default", extensionID: "x", name: "X", version: "1", permissions: permissions, path: "/x", fromStore: fromStore)
    }

    @Test func gradesRiskByCapability() {
        #expect(ext(["storage", "https://example.com/*"]).risk == .low)
        #expect(ext(["<all_urls>", "webRequest"]).risk == .medium)
        #expect(ext(["cookies"]).risk == .medium)
        #expect(ext(["proxy"]).risk == .high)
        #expect(ext(["debugger"]).risk == .high)
        #expect(ext(["management"]).risk == .high)
        #expect(ext(["<all_urls>"], fromStore: false).risk == .high)
        #expect(ext(["storage"], fromStore: false).risk == .low)
        #expect(ext(["proxy"]).riskReasons.first?.contains("traffic") == true)
    }

    @Test func capabilitiesAreReadable() {
        let caps = ext(["<all_urls>", "cookies", "webRequest", "tabs", "nativeMessaging"]).capabilities
        #expect(caps == [.allSites, .cookies, .network, .nativeApp, .tabs])
        #expect(caps.allSatisfy { !$0.explanation.isEmpty })
    }

    @Test func storeLinks() {
        #expect(ext([]).storeURL?.absoluteString == "https://chromewebstore.google.com/detail/x")
    }

    @Test func parsesFirefoxAddonsSkippingSystemOnes() {
        let json = #"{"addons":[{"id":"ublock0@raymondhill.net","type":"extension","location":"app-profile","version":"1.60","signedState":2,"defaultLocale":{"name":"uBlock Origin"},"userPermissions":{"permissions":["webRequest"],"origins":["<all_urls>"]}},{"id":"formautofill@mozilla.org","type":"extension","location":"app-system-defaults"}]}"#
        let addons = FirefoxExtensions.parse(Data(json.utf8), profile: "abc.default", profileDir: "/p")
        #expect(addons.map(\.name) == ["uBlock Origin"])
        #expect(addons.first?.risk == .medium && addons.first?.fromStore == true)
    }

    @Test func parsesPluginkitOutput() {
        let output = """
             com.adguard.safari.AdGuard.Extension(1.11.12)
                        Path = /nonexistent/AdGuard Safari Extension.appex
                Display Name = AdGuard
               Parent Bundle = /nonexistent/AdGuard for Safari.app
        +    com.example.Blocker(2.0)
                        Path = /nonexistent/Blocker.appex
        """
        let parsed = SafariExtensions.parse(output)
        #expect(parsed.map(\.name) == ["AdGuard", "com.example.Blocker"])
        #expect(parsed.first?.version == "1.11.12")
        #expect(SafariExtensions.parse("").isEmpty)
    }
}
