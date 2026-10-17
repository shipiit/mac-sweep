import Foundation
import Testing
@testable import MacSweepCore

@Suite struct ThreatRulesTests {
    func facts(_ name: String, _ kind: FileKind, _ signature: SignatureStatus? = nil, gatekeeper: GatekeeperVerdict = .notChecked,
               quarantined: Bool = false) -> FileFacts {
        FileFacts(path: "/Users/x/Downloads/" + name, kind: kind, signature: signature, gatekeeper: gatekeeper, isQuarantined: quarantined)
    }

    @Test func classifiesKinds() {
        #expect(FileKind.classify(name: "A.app", isExecutable: false, isMachO: false) == .app)
        #expect(FileKind.classify(name: "x.PKG", isExecutable: false, isMachO: false) == .installerPackage)
        #expect(FileKind.classify(name: "x.dmg", isExecutable: false, isMachO: false) == .diskImage)
        #expect(FileKind.classify(name: "run.command", isExecutable: true, isMachO: false) == .script)
        #expect(FileKind.classify(name: "tool", isExecutable: true, isMachO: true) == .executable)
        #expect(FileKind.classify(name: "notes", isExecutable: false, isMachO: false) == .other)
        #expect(FileKind.classify(name: "photo.jpg", isExecutable: false, isMachO: false) == .document)
    }

    @Test func disguisedProgramsAreHigh() {
        let verdict = ThreatRules.assess(facts("invoice.pdf.app", .app, .developer(teamID: "T")))
        #expect(verdict?.severity == .high && verdict?.isAutoQuarantine == true)
        #expect(ThreatRules.assess(facts("photo.jpg.command", .script))?.severity == .high)
        #expect(ThreatRules.isDisguised("report     .app"))
        #expect(!ThreatRules.isDisguised("my.project.app"))
        #expect(!ThreatRules.isDisguised("Visual Studio Code.app"))
    }

    @Test func signatureAndGatekeeperRules() {
        #expect(ThreatRules.assess(facts("Tool.app", .app, .invalid, quarantined: true))?.severity == .high)
        #expect(ThreatRules.assess(facts("Tool.app", .app, .invalid))?.severity == .medium, "installed apps that changed themselves aren't threats")
        #expect(ThreatRules.assess(facts("Tool.app", .app, .unsigned, quarantined: true))?.severity == .high)
        #expect(ThreatRules.assess(facts("Tool.app", .app, .unsigned))?.severity == .medium)
        #expect(ThreatRules.assess(facts("Setup.pkg", .installerPackage, .unsigned))?.severity == .medium)
        #expect(ThreatRules.assess(facts("cli", .executable, .unsigned, quarantined: true))?.severity == .medium)
        #expect(ThreatRules.assess(facts("cli", .executable, .unsigned)) == nil, "locally built tools are fine")
        #expect(ThreatRules.assess(facts("App.app", .app, .developer(teamID: "T"), gatekeeper: .rejected("Unnotarized Developer ID"), quarantined: true))?.severity == .high)
        #expect(ThreatRules.assess(facts("App.app", .app, .developer(teamID: "T"), gatekeeper: .rejected("x")))?.severity == .medium)
        #expect(ThreatRules.assess(facts("App.app", .app, .developer(teamID: "T"), gatekeeper: .accepted)) == nil)
        #expect(ThreatRules.assess(facts("App.app", .app, .apple)) == nil)
    }

    @Test func scriptsAdwareAndHiddenFiles() {
        #expect(ThreatRules.assess(facts("install.command", .script, quarantined: true))?.severity == .medium)
        #expect(ThreatRules.assess(facts("install.command", .script)) == nil)
        #expect(ThreatRules.assess(facts("tool.py", .script, quarantined: true)) == nil, "source files open in an editor")
        #expect(ThreatRules.assess(facts("setup.sh", .script, quarantined: true)) == nil)
        let adware = ThreatRules.assess(facts("MacKeeper.app", .app, .developer(teamID: "T")))
        #expect(adware?.severity == .high && adware?.reasons.first?.contains("mackeeper") == true)
        #expect(ThreatRules.assess(facts(".helper", .executable, .adHoc))?.severity == .high)
        #expect(ThreatRules.assess(facts("readme.txt", .document)) == nil)
    }

    @Test func multipleReasonsKeepTheWorst() {
        let verdict = ThreatRules.assess(facts("doc.pdf.app", .app, .unsigned, quarantined: false))
        #expect(verdict?.severity == .high && verdict?.reasons.count == 2)
    }
}

@Suite struct ThreatScannerTests {
    @Test func parsesPackageSignatures() {
        #expect(ThreatScanner.parsePackageSignature("Package \"x.pkg\":\n   Status: no signature", status: 1) == .unsigned)
        #expect(ThreatScanner.parsePackageSignature("Status: signed by a developer certificate issued by Apple for distribution\n   1. Developer ID Installer: Acme (ABCDE12345)", status: 0)
            == .developer(teamID: "ABCDE12345"))
        #expect(ThreatScanner.parsePackageSignature("Status: signed Apple Software", status: 0) == .apple)
        #expect(ThreatScanner.parsePackageSignature("Status: signed by a revoked certificate", status: 1) == .invalid)
        #expect(ThreatScanner.parsePackageSignature("", status: 0) == .unsigned)
    }

    @Test func parsesGatekeeper() {
        #expect(ThreatScanner.parseGatekeeper("x.app: accepted\nsource=Notarized Developer ID", status: 0) == .accepted)
        #expect(ThreatScanner.parseGatekeeper("x.app: rejected\nsource=Unnotarized Developer ID", status: 3) == .rejected("rejected"))
        #expect(ThreatScanner.parseGatekeeper("", status: 3) == .rejected("not allowed to run"))
    }

    @Test func findsCandidatesAndSkipsNoise() async throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let manager = FileManager.default
        try manager.createDirectory(atPath: root + "/Fake.pdf.app/Contents/MacOS", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: root + "/iCloud.im.vector.app/data", withIntermediateDirectories: true)
        try manager.createDirectory(atPath: root + "/node_modules/pkg", withIntermediateDirectories: true)
        try "#!/bin/sh".write(toFile: root + "/node_modules/pkg/run.command", atomically: true, encoding: .utf8)
        try "#!/bin/sh".write(toFile: root + "/setup.command", atomically: true, encoding: .utf8)
        try "hello".write(toFile: root + "/notes.txt", atomically: true, encoding: .utf8)
        try "hello".write(toFile: root + "/song.mp3.command", atomically: true, encoding: .utf8)
        var seen: [String] = []
        ThreatScanner.walk(root) { seen.append(($0 as NSString).lastPathComponent); return true }
        #expect(seen.contains("Fake.pdf.app") && !seen.contains("MacOS") && !seen.contains("run.command"))
        #expect(!seen.contains("iCloud.im.vector.app"), "a folder named .app without bundle structure isn't an app")
        let verdicts = await ThreatScanner.scan(roots: [root])
        #expect(verdicts.map(\.facts.name).sorted() == ["Fake.pdf.app", "song.mp3.command"])
        #expect(verdicts.allSatisfy { $0.severity == .high })
        #expect(await ThreatScanner.scan(roots: [root + "/missing"]).isEmpty)
    }

    @Test func detectsMachOMagic() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0, 0]).write(to: URL(fileURLWithPath: root + "/bin"))
        try Data("text".utf8).write(to: URL(fileURLWithPath: root + "/txt"))
        #expect(ThreatScanner.isMachO(root + "/bin") && !ThreatScanner.isMachO(root + "/txt") && !ThreatScanner.isMachO(root + "/none"))
    }
}

@Suite struct QuarantineStoreTests {
    @Test func quarantinesRestoresAndKeepsExecuteBits() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let file = root + "/Downloads/evil.pdf.command"
        try FileManager.default.createDirectory(atPath: root + "/Downloads", withIntermediateDirectories: true)
        try "#!/bin/sh".write(toFile: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file)
        let store = QuarantineStore(root: root + "/Q")
        let verdict = ThreatVerdict(facts: FileFacts(path: file, kind: .script, signature: nil), severity: .high, reasons: ["Disguised"])
        let item = try store.quarantine(verdict)
        #expect(!FileManager.default.fileExists(atPath: file))
        #expect(!FileManager.default.isExecutableFile(atPath: item.storedPath), "quarantined copy can't run")
        #expect(store.items().map(\.id) == [item.id] && item.executables == [""])
        try store.restore(item)
        #expect(FileManager.default.isExecutableFile(atPath: file))
        #expect(store.items().isEmpty)
    }

    @Test func refusesRestoreOverExistingFileAndHandlesMissing() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let file = root + "/a.app"
        try "x".write(toFile: file, atomically: true, encoding: .utf8)
        let store = QuarantineStore(root: root + "/Q")
        let verdict = ThreatVerdict(facts: FileFacts(path: file, kind: .app, signature: .invalid), severity: .high, reasons: ["Broken"])
        let item = try store.quarantine(verdict)
        try "new".write(toFile: file, atomically: true, encoding: .utf8)
        #expect(throws: QuarantineStore.StoreError.destinationTaken(file)) { try store.restore(item) }
        #expect(throws: QuarantineStore.StoreError.missing) { try store.quarantine(verdict.withPath(root + "/gone")) }
        try store.discard(item)
        #expect(store.items().isEmpty)
        #expect(QuarantineStore(root: root + "/empty").items().isEmpty)
    }
}

private extension ThreatVerdict {
    func withPath(_ path: String) -> ThreatVerdict {
        ThreatVerdict(facts: FileFacts(path: path, kind: facts.kind, signature: facts.signature), severity: severity, reasons: reasons)
    }
}
