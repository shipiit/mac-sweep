import Foundation
import Testing
@testable import MacSweepCore

@Suite struct TCCParserTests {
    static let userJSON = """
        [{"service":"kTCCServiceCamera","client":"us.zoom.xos","client_type":0,"auth_value":2,"indirect_object_identifier":"UNUSED","last_modified":1700000000},
        {"service":"kTCCServiceMicrophone","client":"com.example.denied","client_type":0,"auth_value":0,"indirect_object_identifier":null,"last_modified":0},
        {"service":"kTCCServiceAppleEvents","client":"com.example.auto","client_type":0,"auth_value":2,"indirect_object_identifier":"com.apple.finder","last_modified":"1700000100"},
        {"service":"kTCCServicePhotos","client":"com.example.limited","client_type":0,"auth_value":3,"last_modified":1700000000},
        {"service":"kTCCServiceAccessibility","client":"/usr/local/bin/tool","client_type":1,"auth_value":2,"last_modified":1700000000},
        {"service":"kTCCServiceLiverpool","client":"com.apple.imagent","client_type":0,"auth_value":5}]
        """

    @Test func parsesRowsClientTypesAndAuthorization() throws {
        let entries = try #require(TCCParser.parse(Self.userJSON, database: .user))
        #expect(entries.count == 6)
        #expect(entries[0].client == .bundleID("us.zoom.xos"))
        #expect(entries[0].authorization == .allowed)
        #expect(entries[0].target == nil)
        #expect(entries[0].lastModified == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(entries[1].authorization == .denied)
        #expect(entries[1].lastModified == nil)
        #expect(entries[2].target == "com.apple.finder")
        #expect(entries[2].lastModified == Date(timeIntervalSince1970: 1_700_000_100))
        #expect(entries[3].authorization == .limited)
        #expect(entries[3].authorization.isGranted)
        #expect(entries[4].client == .path("/usr/local/bin/tool"))
        #expect(entries[5].authorization == .other(5))
        #expect(!entries[5].authorization.isGranted)
    }

    @Test func emptyOutputIsAnEmptyList() {
        #expect(TCCParser.parse("", database: .user) == [])
        #expect(TCCParser.parse("  \n", database: .system) == [])
        #expect(TCCParser.parse("[]", database: .system) == [])
    }

    @Test func garbageIsNil() {
        #expect(TCCParser.parse("Error: near line 1", database: .user) == nil)
        #expect(TCCParser.parse("{\"service\":1}", database: .user) == nil)
        #expect(TCCParser.parse("[{\"broken\"", database: .user) == nil)
    }

    @Test func skipsRowsMissingRequiredFields() {
        let json = #"[{"service":"kTCCServiceCamera","client":"","auth_value":2},{"client":"a","auth_value":2},{"service":"kTCCServiceCamera","client":"a"}]"#
        #expect(TCCParser.parse(json, database: .user) == [])
    }

    @Test func classifiesPermissionDenialAsNeedingFullDiskAccess() {
        let denied = ShellResult(status: 1, stdout: "", stderr: "Error: unable to open database \"/Library/x/TCC.db\": authorization denied")
        #expect(TCCParser.classify(denied, database: .system) == .needsFullDiskAccess)
        let cantOpen = ShellResult(status: 1, stdout: "", stderr: "Error: unable to open database \"x\": unable to open database file")
        #expect(TCCParser.classify(cantOpen, database: .user) == .needsFullDiskAccess)
        let eperm = ShellResult(status: 1, stdout: "", stderr: "Error: Operation not permitted")
        #expect(TCCParser.classify(eperm, database: .user) == .needsFullDiskAccess)
    }

    @Test func otherFailuresDoNotLeakStderr() {
        let result = TCCParser.classify(ShellResult(status: 2, stdout: "", stderr: "Error: secret /Users/someone/path"), database: .user)
        #expect(result == .failed("sqlite3 exited with status 2"))
        #expect(result.entries.isEmpty)
        let garbage = TCCParser.classify(ShellResult(status: 0, stdout: "not json", stderr: ""), database: .user)
        if case .failed = garbage {} else { Issue.record("expected failure") }
    }

    @Test func successfulReadReturnsEntries() {
        let result = TCCParser.classify(ShellResult(status: 0, stdout: Self.userJSON, stderr: ""), database: .system)
        #expect(result.entries.count == 6)
        #expect(result.entries.allSatisfy { $0.database == .system })
    }

    @Test func databasePaths() {
        #expect(TCCReader.databasePath(.user, home: "/Users/test") == "/Users/test/Library/Application Support/com.apple.TCC/TCC.db")
        #expect(TCCReader.databasePath(.system) == "/Library/Application Support/com.apple.TCC/TCC.db")
    }
}

@Suite struct TCCServiceCatalogTests {
    @Test func knownServicesMapToFriendlyNamesAndPanes() throws {
        let camera = try #require(TCCServiceCatalog.service(for: "kTCCServiceCamera"))
        #expect(camera.title == "Camera")
        #expect(camera.settingsURL?.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        #expect(TCCServiceCatalog.service(for: "kTCCServiceSystemPolicyAllFiles")?.title == "Full Disk Access")
        #expect(TCCServiceCatalog.service(for: "kTCCServicePostEvent")?.paneAnchor == "Privacy_Accessibility")
        #expect(TCCServiceCatalog.service(for: "kTCCServiceAppleEvents")?.paneAnchor == "Privacy_Automation")
    }

    @Test func everyKnownServiceHasAValidURLAndUniqueKey() {
        #expect(Set(TCCServiceCatalog.known.map(\.key)).count == TCCServiceCatalog.known.count)
        #expect(TCCServiceCatalog.known.allSatisfy { $0.settingsURL != nil && !$0.title.isEmpty })
    }

    @Test func unknownServicesFallBackToReadableNames() {
        #expect(TCCServiceCatalog.service(for: "kTCCServiceUbiquity") == nil)
        #expect(TCCServiceCatalog.fallback(for: "kTCCServiceUbiquity").title == "Ubiquity")
        #expect(TCCServiceCatalog.fallback(for: "kTCCService").title == "Other")
        #expect(TCCServiceCatalog.fallback(for: "custom").title == "custom")
        #expect(!TCCServiceCatalog.fallback(for: "x").isPowerful)
        #expect(TCCServiceCatalog.order(of: "kTCCServiceUbiquity") == TCCServiceCatalog.known.count)
    }
}

@Suite struct TCCRiskTests {
    func entry(_ service: String, _ client: TCCEntry.Client = .bundleID("com.x.app"), auth: TCCAuthorization = .allowed) -> TCCEntry {
        TCCEntry(database: .system, serviceKey: service, client: client, authorization: auth)
    }

    func info(_ signature: SignatureStatus?, path: String? = "/Applications/X.app") -> TCCClientInfo {
        TCCClientInfo(name: "X", path: path, signature: signature)
    }

    @Test func trustedAppsAndHarmlessServicesAreNotFlagged() {
        #expect(TCCRisk.assess(entry("kTCCServiceAccessibility"), client: info(.developer(teamID: "T"))) == nil)
        #expect(TCCRisk.assess(entry("kTCCServiceScreenCapture"), client: info(.apple)) == nil)
        #expect(TCCRisk.assess(entry("kTCCServiceCamera"), client: info(.unsigned)) == nil)
    }

    @Test func deniedGrantsAreNeverFlagged() {
        #expect(TCCRisk.assess(entry("kTCCServiceAccessibility", auth: .denied), client: info(.unsigned)) == nil)
        #expect(TCCRisk.assess(entry("kTCCServiceAccessibility", auth: .other(1)), client: info(nil, path: nil)) == nil)
    }

    @Test func untrustedCodeWithPowerfulGrantsIsFlagged() {
        #expect(TCCRisk.assess(entry("kTCCServiceAccessibility"), client: info(.unsigned))?.severity == .high)
        #expect(TCCRisk.assess(entry("kTCCServiceSystemPolicyAllFiles"), client: info(.invalid))?.severity == .high)
        #expect(TCCRisk.assess(entry("kTCCServiceListenEvent"), client: info(.adHoc))?.severity == .medium)
        #expect(TCCRisk.assess(entry("kTCCServicePostEvent"), client: info(.missing))?.severity == .low)
        let unknown = TCCRisk.assess(entry("kTCCServiceScreenCapture"), client: info(nil, path: nil))
        #expect(unknown?.severity == .medium)
        #expect(unknown?.reason.contains("Screen & System Audio Recording") == true)
    }

    @Test func suspiciousLocationsBeatSignature() {
        let flag = TCCRisk.assess(entry("kTCCServiceAccessibility", .path("/private/tmp/agent")),
                                  client: info(.developer(teamID: "T"), path: nil))
        #expect(flag?.severity == .high)
        let downloads = TCCRisk.assess(entry("kTCCServiceAccessibility"), client: info(.apple, path: "/Users/test/Downloads/X.app"))
        #expect(downloads?.severity == .high)
    }

    @Test func unresolvedNames() {
        #expect(TCCClientInfo.unresolved(.bundleID("com.vendor.Tool")).name == "Tool")
        #expect(TCCClientInfo.unresolved(.bundleID("plain")).name == "plain")
        #expect(TCCClientInfo.unresolved(.path("/usr/local/bin/tool")).name == "tool")
        #expect(TCCClientInfo.unresolved(.path("/x")).signature == nil)
    }

    @Test func groupsByServiceInCatalogOrderWithGrantedFirst() {
        let groups = TCCRisk.group([
            entry("kTCCServiceUbiquity"), entry("kTCCServiceCamera", .bundleID("b"), auth: .denied),
            entry("kTCCServiceCamera", .bundleID("c")), entry("kTCCServiceAccessibility"),
        ])
        #expect(groups.map(\.service.key) == ["kTCCServiceAccessibility", "kTCCServiceCamera", "kTCCServiceUbiquity"])
        #expect(groups[1].entries.map(\.client.raw) == ["c", "b"])
        #expect(groups[1].allowedCount == 1)
        #expect(TCCRisk.group([]).isEmpty)
    }

    @Test func appleSystemClients() {
        #expect(TCCRisk.isAppleSystemClient(.bundleID("com.apple.Terminal")))
        #expect(TCCRisk.isAppleSystemClient(.path("/usr/libexec/sshd-keygen-wrapper")))
        #expect(!TCCRisk.isAppleSystemClient(.bundleID("com.applenot.x")))
        #expect(!TCCRisk.isAppleSystemClient(.path("/opt/homebrew/bin/x")))
    }

    @Test func entryIdentityIncludesTarget() {
        let a = TCCEntry(database: .user, serviceKey: "kTCCServiceAppleEvents", client: .bundleID("x"), authorization: .allowed, target: "com.apple.finder")
        let b = TCCEntry(database: .user, serviceKey: "kTCCServiceAppleEvents", client: .bundleID("x"), authorization: .allowed, target: "com.apple.mail")
        #expect(a.id != b.id)
    }
}
