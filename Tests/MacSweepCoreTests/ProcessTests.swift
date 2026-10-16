import Darwin
import Foundation
import Testing
@testable import MacSweepCore

@Suite struct MemoryTrendTests {
    func samples(_ values: [UInt64], step: TimeInterval = 3) -> [MemorySample] {
        values.enumerated().map { MemorySample(time: Double($0.offset) * step, bytes: $0.element) }
    }

    @Test func steadyGrowthIsFlagged() {
        let mb: UInt64 = 1 << 20
        let summary = MemoryTrend.summarize(samples((0..<12).map { 500 * mb + UInt64($0) * 10 * mb }))
        #expect(summary.isSteadilyGrowing)
        #expect(summary.bytesPerMinute > 0)
        #expect(summary.growth == Int64(110 * mb))
    }

    @Test func flatMemoryIsNotFlagged() {
        #expect(!MemoryTrend.summarize(samples(Array(repeating: 1 << 30, count: 20))).isSteadilyGrowing)
    }

    @Test func smallGrowthIsNotFlagged() {
        let summary = MemoryTrend.summarize(samples((0..<20).map { 100 << 20 + UInt64($0) << 10 }))
        #expect(!summary.isSteadilyGrowing)
    }

    @Test func noisyGrowthIsNotFlagged() {
        let mb: UInt64 = 1 << 20
        let values: [UInt64] = (0..<12).map { $0 % 2 == 0 ? 100 * mb + UInt64($0) * 20 * mb : 80 * mb }
        #expect(!MemoryTrend.summarize(samples(values)).isSteadilyGrowing)
    }

    @Test func tooFewSamplesAreNeverFlagged() {
        #expect(!MemoryTrend.summarize(samples([0, 1 << 30, 2 << 30])).isSteadilyGrowing)
        #expect(MemoryTrend.summarize([]) == .flat)
        #expect(MemoryTrend.summarize(samples([5])) == .flat)
    }

    @Test func shrinkingMemoryHasNegativeSlope() {
        let summary = MemoryTrend.summarize(samples((0..<12).map { UInt64(1000 - $0 * 10) << 20 }))
        #expect(summary.bytesPerMinute < 0)
        #expect(!summary.isSteadilyGrowing)
    }
}

@Suite struct ProcessTests {
    @Test func samplesIncludeThisProcessWithMemory() throws {
        let me = try #require(ProcessSampler.sample().first { $0.pid == getpid() })
        #expect((me.memory ?? 0) > 0)
        #expect(me.user == ProcReader.userName(getuid()))
        #expect(me.threads ?? 0 >= 1)
    }

    @Test func cpuPercentMath() {
        #expect(ProcessSampler.cpuPercent(previous: 0, current: 500_000_000, elapsed: 1) == 50)
        #expect(ProcessSampler.cpuPercent(previous: nil, current: 5, elapsed: 1) == nil)
        #expect(ProcessSampler.cpuPercent(previous: 10, current: 5, elapsed: 1) == nil)
        #expect(ProcessSampler.cpuPercent(previous: 0, current: 5, elapsed: 0) == nil)
    }

    @Test func displayNamePrefersBundleName() {
        #expect(ProcReader.displayName(name: "Google Chrome He", path: "/Applications/Google Chrome.app/Contents/Frameworks/x/Google Chrome Helper") == "Google Chrome Helper")
        #expect(ProcReader.displayName(name: "Slack", path: "/Applications/Slack.app/Contents/MacOS/Slack") == "Slack")
        #expect(ProcReader.displayName(name: "node", path: nil) == "node")
    }

    @Test func procArgsParsing() {
        var bytes: [UInt8] = [2, 0, 0, 0]
        bytes += Array("/usr/bin/node".utf8) + [0, 0, 0]
        bytes += Array("node".utf8) + [0] + Array("server.js".utf8) + [0]
        bytes += Array("SECRET=1".utf8) + [0]
        #expect(ProcArgs.parse(bytes) == ["node", "server.js"])
        #expect(ProcArgs.parse([1, 0]) == nil)
        #expect(ProcArgs.parse([0, 0, 0, 0]) == [])
    }

    @Test func readsOwnArgumentsAndWorkingDirectory() {
        #expect(ProcArgs.arguments(pid: getpid())?.isEmpty == false)
        #expect(ProcReader.workingDirectory(getpid()) == FileManager.default.currentDirectoryPath)
    }

    @Test func systemMemoryIsConsistent() throws {
        let stats = try #require(SystemMemory.read())
        #expect(stats.total == ProcessInfo.processInfo.physicalMemory)
        #expect(stats.used > 0 && stats.used <= stats.total)
    }

    @Test func refusesCriticalProcesses() {
        #expect(ProcessKiller.send(SIGTERM, to: 1, name: "launchd") != .sent)
        #expect(ProcessKiller.send(SIGTERM, to: getpid(), name: "x") != .sent)
        #expect(ProcessKiller.send(SIGTERM, to: 4242, name: "WindowServer") != .sent)
        #expect(ProcessKiller.refusalReason(pid: 4242, name: "node") == nil)
    }

    @Test func killsASpawnedProcess() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["300"]
        try process.run()
        #expect(ProcessKiller.send(SIGTERM, to: process.processIdentifier, name: "sleep") == .sent)
        process.waitUntilExit()
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(ProcessKiller.send(SIGTERM, to: process.processIdentifier, name: "sleep") == .notFound)
    }

    @Test func otherUsersProcessIsNotPermitted() {
        let root = ProcessSampler.sample().first { $0.uid == 0 && !ProcessKiller.protectedNames.contains($0.name) && $0.pid > 1 }
        guard let root, getuid() != 0 else { return }
        #expect(ProcessKiller.send(0, to: root.pid, name: root.name) == .notPermitted)
    }
}

@Suite struct ShellTests {
    @Test func capturesOutputAndStatus() async throws {
        let result = try await Shell.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        #expect(result.stdout == "out\n")
        #expect(result.stderr == "err\n")
        #expect(result.status == 3)
    }

    @Test func missingExecutableThrows() async {
        await #expect(throws: ShellError.self) { try await Shell.run("/no/such/binary", []) }
    }
}

@Suite struct CategoryTests {
    let home = "/Users/test"

    @Test(arguments: [
        ("/Users/test/.ollama/models", StorageCategory.ai),
        ("/Users/test/.cache/huggingface/hub", .ai),
        ("/Users/test/.cache/uv", .caches),
        ("/Users/test/.npm", .caches),
        ("/Users/test/Library/Developer/Xcode", .sdks),
        ("/Users/test/Desktop/app", .code),
        ("/Users/test/Pictures/Photos Library.photoslibrary", .media),
        ("/Users/test/Library/Application Support/X", .system),
        ("/Users/test/.vscode", .devTools),
        ("/Applications/Xcode.app", .system),
    ])
    func classifiesKnownLocations(path: String, expected: StorageCategory) {
        #expect(StorageCategory.classify(path: path, home: home) == expected)
    }

    @Test func gitRepoAnywhereIsCode() {
        #expect(StorageCategory.classify(path: "/Users/test/random/repo", home: home, isGitRepo: true) == .code)
    }

    @Test func unknownPathsInherit() {
        #expect(StorageCategory.classify(path: "/Users/test/random/thing", home: home) == nil)
        #expect(StorageCategory.classify(path: "/Users/test/.vscode/extensions", home: home) == nil)
    }
}

@Suite struct SystemLoadTests {
    @Test func cpuUsageMath() {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let b = CPUTicks(user: 200, system: 100, idle: 1700, nice: 0)
        #expect(abs(SystemLoad.usage(from: a, to: b) - 0.15) < 0.0001)
        #expect(SystemLoad.usage(from: b, to: a) == 0)
        #expect(SystemLoad.usage(from: a, to: a) == 0)
    }

    @Test func liveReadingsAreAvailable() throws {
        let ticks = try #require(SystemLoad.cpuTicks())
        #expect(ticks.total > 0)
        #expect(SystemLoad.networkCounters() != nil)
        #expect(SystemLoad.loadAverage().count == 3)
    }

    @Test func rateMath() {
        #expect(SystemLoad.rate(from: 100, to: 300, elapsed: 2) == 100)
        #expect(SystemLoad.rate(from: 300, to: 100, elapsed: 2) == 0)
        #expect(SystemLoad.rate(from: 0, to: 100, elapsed: 0) == 0)
    }
}

@Suite struct IdleAppsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let mb: UInt64 = 1 << 20

    func proc(_ pid: Int32, ppid: Int32 = 1, path: String?, memory: UInt64) -> ProcessSnapshot {
        ProcessSnapshot(pid: pid, ppid: ppid, name: "p\(pid)", path: path, uid: 501, user: "u", memory: memory, cpuTimeNanos: nil, threads: nil, started: nil)
    }

    func app(_ pid: Int32, _ id: String, path: String, lastActive: Date?, launched: Date? = nil, front: Bool = false) -> RunningAppSnapshot {
        RunningAppSnapshot(pid: pid, bundleID: id, name: id, bundlePath: path, launchDate: launched, lastActive: lastActive, isFrontmost: front)
    }

    @Test func sumsHelpersInsideBundleAndChildren() {
        let chrome = app(10, "com.google.Chrome", path: "/Applications/Google Chrome.app", lastActive: nil)
        let processes = [
            proc(10, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", memory: 300 * mb),
            proc(11, ppid: 10, path: "/Applications/Google Chrome.app/Contents/Frameworks/Helper (Renderer)", memory: 200 * mb),
            proc(12, ppid: 11, path: "/usr/bin/something", memory: 50 * mb),
            proc(13, path: "/Applications/Other.app/Contents/MacOS/Other", memory: 999 * mb),
        ]
        let family = IdleApps.processesBelonging(to: chrome, in: processes)
        #expect(Set(family.map(\.pid)) == [10, 11, 12])
    }

    @Test func suggestsAppsIdleLongerThanThreshold() {
        let processes = [proc(1, path: "/A.app/Contents/MacOS/A", memory: 500 * mb), proc(2, path: "/B.app/Contents/MacOS/B", memory: 500 * mb)]
        let apps = [
            app(1, "com.a", path: "/A.app", lastActive: now.addingTimeInterval(-3 * 3_600)),
            app(2, "com.b", path: "/B.app", lastActive: now.addingTimeInterval(-10 * 60)),
        ]
        let idle = IdleApps.find(apps: apps, processes: processes, watchingSince: now.addingTimeInterval(-86_400), now: now)
        #expect(idle.map(\.app.bundleID) == ["com.a"])
        #expect(idle.first?.isAtLeast == false)
    }

    @Test func unseenAppsAreIdleSinceWatchingStarted() {
        let processes = [proc(1, path: "/A.app/Contents/MacOS/A", memory: 500 * mb)]
        let started = now.addingTimeInterval(-3 * 3_600)
        let old = app(1, "com.a", path: "/A.app", lastActive: nil, launched: now.addingTimeInterval(-86_400))
        let idle = IdleApps.find(apps: [old], processes: processes, watchingSince: started, now: now)
        #expect(idle.first?.idleSince == started && idle.first?.isAtLeast == true)
        let fresh = app(1, "com.a", path: "/A.app", lastActive: nil, launched: now.addingTimeInterval(-600))
        #expect(IdleApps.find(apps: [fresh], processes: processes, watchingSince: started, now: now).isEmpty)
    }

    @Test func neverSuggestsFrontmostProtectedExcludedOrSmallApps() {
        let processes = [proc(1, path: "/A.app/x", memory: 500 * mb), proc(2, path: "/F.app/x", memory: 500 * mb),
                         proc(3, path: "/S.app/x", memory: 10 * mb), proc(4, path: "/E.app/x", memory: 500 * mb)]
        let longAgo = now.addingTimeInterval(-86_400)
        let apps = [
            app(1, "com.a", path: "/A.app", lastActive: longAgo, front: true),
            app(2, "com.apple.finder", path: "/F.app", lastActive: longAgo),
            app(3, "com.small", path: "/S.app", lastActive: longAgo),
            app(4, "com.excluded", path: "/E.app", lastActive: longAgo),
        ]
        #expect(IdleApps.find(apps: apps, processes: processes, watchingSince: longAgo, now: now, excluded: ["com.excluded"]).isEmpty)
    }

    @Test func sortsByMemory() {
        let longAgo = now.addingTimeInterval(-86_400)
        let processes = [proc(1, path: "/A.app/x", memory: 200 * mb), proc(2, path: "/B.app/x", memory: 900 * mb)]
        let apps = [app(1, "com.a", path: "/A.app", lastActive: longAgo), app(2, "com.b", path: "/B.app", lastActive: longAgo)]
        #expect(IdleApps.find(apps: apps, processes: processes, watchingSince: longAgo, now: now).map(\.app.bundleID) == ["com.b", "com.a"])
    }
}

@Suite struct ProcessGroupsTests {
    func proc(_ pid: Int32, _ name: String, ppid: Int32 = 1, path: String?, mb: UInt64) -> ProcessSnapshot {
        ProcessSnapshot(pid: pid, ppid: ppid, name: name, path: path, uid: 501, user: "u", memory: mb << 20, cpuTimeNanos: nil, threads: 2, started: nil)
    }

    @Test func groupsAppsWithHelpersAndNamesTheRest() {
        let processes = [
            proc(10, "Google Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", mb: 500),
            proc(11, "Helper", ppid: 10, path: "/Applications/Google Chrome.app/Contents/Frameworks/Helper", mb: 700),
            proc(20, "Python", path: "/usr/bin/python3", mb: 300),
            proc(21, "Python", path: "/usr/bin/python3", mb: 200),
            proc(30, "redis-server", path: "/opt/redis", mb: 50),
        ]
        let chrome = RunningAppSnapshot(pid: 10, bundleID: "com.google.Chrome", name: "Google Chrome",
                                        bundlePath: "/Applications/Google Chrome.app", launchDate: nil, lastActive: nil, isFrontmost: false)
        let groups = ProcessGroups.group(processes: processes, apps: [chrome])
        #expect(groups.map(\.name) == ["Google Chrome", "Python", "redis-server"])
        #expect(groups[0].processes.count == 2 && groups[0].memory == 1_200 << 20)
        #expect(groups[1].processes.count == 2 && groups[1].kind == .named)
        #expect(groups.reduce(0) { $0 + $1.processes.count } == processes.count)
    }

    @Test func emptyInputs() {
        #expect(ProcessGroups.group(processes: [], apps: []).isEmpty)
    }
}
