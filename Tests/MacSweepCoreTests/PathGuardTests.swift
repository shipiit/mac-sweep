import Foundation
import Testing
@testable import MacSweepCore

@Suite struct PathGuardTests {
    let home = Fixtures.home

    @Test(arguments: [
        "/Users/test/.npm/_cacache",
        "/Users/test/Desktop/project/node_modules",
        "/Users/test/Library/Caches/Homebrew",
        "/Users/test/Downloads/installer.dmg",
        "/Applications/Some App.app",
        "/Users/Shared/old",
    ])
    func allowsOrdinaryTargets(path: String) {
        #expect(PathGuard.canRemove(path, home: home))
    }

    @Test(arguments: [
        "/Users/test", "/Users/test/", "/Users/test/Desktop", "/Users/test/Library", "/Users/test/Library/Caches",
        "/Users/test/Documents", "/Users/test/.Trash", "/Applications", "/Users/Shared",
    ])
    func refusesStandardRoots(path: String) {
        #expect(!PathGuard.canRemove(path, home: home))
    }

    @Test(arguments: [
        "/Users/test/.ssh/id_ed25519", "/Users/test/.ssh", "/Users/test/.aws/credentials",
        "/Users/test/Library/Keychains/login.keychain-db", "/Users/test/Library/Preferences/com.apple.finder.plist",
        "/Users/test/Library/Application Support/com.apple.TCC/TCC.db", "/Applications/Utilities/Terminal.app",
    ])
    func refusesSecretsAndSystemState(path: String) {
        #expect(!PathGuard.canRemove(path, home: home))
    }

    @Test(arguments: ["/System/Library", "/usr/bin/ls", "/private/var/db", "/Library/Caches/x", "/Users/other/file", "relative/path", ""])
    func refusesEverythingOutsideAllowedRoots(path: String) {
        #expect(!PathGuard.canRemove(path, home: home))
    }

    @Test func allowsThirdPartyPreferencesButNotApples() {
        #expect(PathGuard.canRemove("/Users/test/Library/Preferences/com.tinyspeck.slackmacgap.plist", home: home))
        #expect(!PathGuard.canRemove("/Users/test/Library/Preferences/com.apple.dock.plist", home: home))
        #expect(!PathGuard.canRemove("/Users/test/Library/Preferences", home: home))
        #expect(!PathGuard.canRemove("/Users/test/Library/Preferences/ByHost/x.plist", home: home))
    }

    @Test func refusesTraversalOutOfHome() {
        #expect(!PathGuard.canRemove("/Users/test/../other/file", home: home))
        #expect(!PathGuard.canRemove("/Users/test/Desktop/../.ssh", home: home))
    }

    @Test func refusesPrefixLookalikeOfHome() {
        #expect(!PathGuard.canRemove("/Users/testing/file", home: home))
    }

    @Test func honoursExtraProtectedPaths() {
        #expect(!PathGuard.canRemove("/Applications/MacSweep.app", home: home, extraProtected: ["/Applications/MacSweep.app"]))
        #expect(!PathGuard.canRemove("/Applications/MacSweep.app/Contents", home: home, extraProtected: ["/Applications/MacSweep.app"]))
    }

    @Test func reasonExplainsRefusal() {
        #expect(PathGuard.reason("/Users/test/.ssh/id_rsa", home: home) != nil)
        #expect(PathGuard.reason("/Users/test/.npm/x", home: home) == nil)
    }
}
