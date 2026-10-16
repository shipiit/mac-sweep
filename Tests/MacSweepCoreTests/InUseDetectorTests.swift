import Foundation
import Testing
@testable import MacSweepCore

@Suite struct InUseDetectorTests {
    let home = Fixtures.home

    @Test func flagsProcessRunningFromTarget() {
        let conflicts = InUseDetector.conflicts(
            targets: [home + "/.nvm/versions/node/v20"],
            processes: [RunningProcessInfo(pid: 10, name: "node", executable: home + "/.nvm/versions/node/v20/bin/node", workingDirectory: "/")],
            apps: [], home: home
        )
        #expect(conflicts.first?.owner == "node")
    }

    @Test func flagsProcessWorkingInsideTarget() {
        let conflicts = InUseDetector.conflicts(
            targets: [home + "/proj/.next"],
            processes: [RunningProcessInfo(pid: 11, name: "next-server", executable: "/usr/local/bin/node", workingDirectory: home + "/proj/.next/server")],
            apps: [], home: home
        )
        #expect(conflicts.count == 1)
    }

    @Test func flagsOpenAppOwningCache() {
        let apps = [RunningAppInfo(name: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
                    RunningAppInfo(name: "Google Chrome", bundleID: "com.google.Chrome")]
        let targets = [home + "/Library/Application Support/Slack/Cache", home + "/Library/Caches/com.google.Chrome",
                       home + "/Library/Caches/Homebrew"]
        let conflicts = InUseDetector.conflicts(targets: targets, processes: [], apps: apps, home: home)
        #expect(Set(conflicts.map(\.targetPath)) == Set(targets.prefix(2)))
    }

    @Test func doesNotFlagUnrelatedOrPrefixLookalikes() {
        let conflicts = InUseDetector.conflicts(
            targets: [home + "/proj/.next"],
            processes: [RunningProcessInfo(pid: 12, name: "node", executable: "/opt/node", workingDirectory: home + "/proj/.next-other")],
            apps: [RunningAppInfo(name: "Notes", bundleID: "com.apple.Notes")], home: home
        )
        #expect(conflicts.isEmpty)
    }

    @Test func flagsScriptsRunFromTargetViaArguments() {
        let mcp = RunningProcessInfo(pid: 67008, name: "node", executable: home + "/.nvm/versions/node/v22/bin/node", workingDirectory: "/",
                                     arguments: ["node", home + "/.npm/_npx/9833c18b2d85bc59/node_modules/.bin/playwright-mcp"])
        let conflicts = InUseDetector.conflicts(targets: [home + "/.npm/_npx", home + "/.npm/_cacache"], processes: [mcp], apps: [], home: home)
        #expect(conflicts.map(\.targetPath) == [home + "/.npm/_npx"])
        #expect(conflicts.first?.reason.contains("script") == true)
    }

    @Test func flagsBuildOutputOfProjectWithRunningDevServer() {
        let dev = RunningProcessInfo(pid: 5, name: "next-server", executable: "/x/node", workingDirectory: home + "/app")
        let conflicts = InUseDetector.conflicts(targets: [home + "/app/.next", home + "/other/.next"], processes: [dev], apps: [], home: home)
        #expect(conflicts.map(\.targetPath) == [home + "/app/.next"])
    }

    @Test func shellInHomeDoesNotBlockEverything() {
        let shell = RunningProcessInfo(pid: 6, name: "zsh", executable: "/bin/zsh", workingDirectory: home)
        #expect(InUseDetector.conflicts(targets: [home + "/.npm"], processes: [shell], apps: [], home: home).isEmpty)
    }

    @Test func emptyInputs() {
        #expect(InUseDetector.conflicts(targets: [], processes: [], apps: [], home: home).isEmpty)
    }

    @Test func ownerHints() {
        #expect(InUseDetector.ownerHint(for: home + "/Library/Application Support/Code/CachedData", home: home) == "Code")
        #expect(InUseDetector.ownerHint(for: home + "/Library/Caches/com.spotify.client", home: home) == "com.spotify.client")
        #expect(InUseDetector.ownerHint(for: home + "/.npm/_cacache", home: home) == nil)
        #expect(InUseDetector.ownerHint(for: home + "/Library/Caches/pip", home: home) == nil)
    }

    @Test func detectsThisTestProcessWorkingDirectory() {
        let cwd = FileManager.default.currentDirectoryPath
        let me = RunningProcessInfo(pid: getpid(), name: "tests", executable: nil, workingDirectory: ProcReader.workingDirectory(getpid()))
        let conflicts = InUseDetector.conflicts(targets: [cwd], processes: [me], apps: [], home: home)
        #expect(conflicts.count == 1)
    }
}
