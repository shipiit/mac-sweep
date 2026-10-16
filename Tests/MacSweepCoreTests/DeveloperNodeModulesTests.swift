import Foundation
import Testing
@testable import MacSweepCore

@Suite struct NodeModulesTests {
    @Test func classifiesActivity() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let day: TimeInterval = 86_400
        #expect(ProjectActivity.classify(lastModified: now, now: now) == .active)
        #expect(ProjectActivity.classify(lastModified: now.addingTimeInterval(-29 * day), now: now) == .active)
        #expect(ProjectActivity.classify(lastModified: now.addingTimeInterval(-30 * day), now: now) == .idle)
        #expect(ProjectActivity.classify(lastModified: now.addingTimeInterval(-89 * day), now: now) == .idle)
        #expect(ProjectActivity.classify(lastModified: now.addingTimeInterval(-90 * day), now: now) == .stale)
        #expect(ProjectActivity.classify(lastModified: nil, now: now) == .stale)
        #expect(ProjectActivity.classify(lastModified: now.addingTimeInterval(day), now: now) == .active)
    }

    @Test func findsFoldersWithoutDescendingIntoThem() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let root = home + "/projects"
        try Fixtures.write(root + "/web/node_modules/react/node_modules/x/index.js", bytes: 10)
        try Fixtures.write(root + "/web/package.json", bytes: 2)
        try Fixtures.write(root + "/mono/packages/api/node_modules/a/index.js", bytes: 10)
        try Fixtures.write(root + "/mono/node_modules/b/index.js", bytes: 10)
        try Fixtures.write(root + "/.hidden/node_modules/c.js", bytes: 1)
        try Fixtures.write(root + "/Library/node_modules/d.js", bytes: 1)
        try Fixtures.write(root + "/a/b/c/d/e/f/node_modules/deep.js", bytes: 1)
        try FileManager.default.createSymbolicLink(atPath: root + "/link", withDestinationPath: root + "/web")

        let found = NodeModulesFinder.find(roots: [root, home + "/missing"], maxDepth: 4)
        #expect(found == [root + "/mono/node_modules", root + "/mono/packages/api/node_modules", root + "/web/node_modules"])
        #expect(NodeModulesFinder.find(roots: []).isEmpty)
    }

    @Test func groupsByGitRoot() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let folders = [home + "/mono/node_modules", home + "/mono/packages/api/node_modules", home + "/loose/node_modules"]
        try FileManager.default.createDirectory(atPath: home + "/mono/.git", withIntermediateDirectories: true)
        let roots = NodeModulesFinder.gitRoots(for: folders)
        #expect(roots == [home + "/mono"])

        let projects = NodeModulesFinder.group(folders, gitRoots: roots)
        #expect(projects.map(\.root) == [home + "/loose", home + "/mono"])
        #expect(projects[1].folders.count == 2)
        #expect(projects[1].name == "mono")
        #expect(NodeModulesFinder.group([], gitRoots: []).isEmpty)
    }

    @Test func nearestRootPrefersInnermost() {
        let roots: Set = ["/a", "/a/b"]
        #expect(NodeModulesFinder.nearestRoot(of: "/a/b/c", in: roots) == "/a/b")
        #expect(NodeModulesFinder.nearestRoot(of: "/a/x", in: roots) == "/a")
        #expect(NodeModulesFinder.nearestRoot(of: "/z", in: roots) == nil)
        #expect(NodeModulesFinder.nearestRoot(of: "/", in: roots) == nil)
    }

    @Test func totalsAndSorting() {
        let small = NodeProject(root: "/b", folders: [NodeModulesFolder(path: "/b/node_modules", size: 10)])
        let big = NodeProject(root: "/a", folders: [NodeModulesFolder(path: "/a/node_modules", size: 50),
                                                     NodeModulesFolder(path: "/a/x/node_modules", size: 25)])
        let pending = NodeProject(root: "/c", folders: [NodeModulesFolder(path: "/c/node_modules")])
        #expect(big.totalSize == 75 && big.isMeasured)
        #expect(pending.totalSize == 0 && !pending.isMeasured)
        #expect(NodeModulesFinder.sorted([small, pending, big]).map(\.root) == ["/a", "/b", "/c"])
        let tie = NodeProject(root: "/0", folders: [])
        #expect(NodeModulesFinder.sorted([pending, tie]).map(\.root) == ["/0", "/c"])
    }

    @Test func lastModifiedUsesNewestMarker() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let project = home + "/app"
        try Fixtures.write(project + "/package.json", bytes: 2)
        let old = Date(timeIntervalSince1970: 1_000_000)
        let newer = Date(timeIntervalSince1970: 2_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: project + "/package.json")
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: project)
        try Fixtures.write(project + "/yarn.lock", bytes: 2)
        try FileManager.default.setAttributes([.modificationDate: newer], ofItemAtPath: project + "/yarn.lock")
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: project)
        #expect(NodeModulesFinder.lastModified(project: project) == newer)
        #expect(NodeModulesFinder.lastModified(project: home + "/missing") == nil)
    }

    @Test func defaultRootIsTheWholeHome() {
        #expect(NodeModulesFinder.defaultRoots(home: "/Users/t") == ["/Users/t"])
    }

    @Test func skipsMediaLibraryAndBundles() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        for path in ["anywhere/web/node_modules", "Pictures/x/node_modules", "Library/y/node_modules", "Tool.app/z/node_modules",
                     "Photos.photoslibrary/node_modules", "a/b/c/d/e/f/node_modules", "a/b/c/d/e/f/g/node_modules"] {
            try FileManager.default.createDirectory(atPath: home + "/" + path, withIntermediateDirectories: true)
        }
        let found = NodeModulesFinder.find(roots: [home]).map { String($0.dropFirst(home.count + 1)) }
        #expect(found == ["a/b/c/d/e/f/node_modules", "anywhere/web/node_modules"])
    }

    @Test func nodeModulesAreTrashableButHomeIsNot() {
        #expect(PathGuard.canRemove("/Users/t/projects/web/node_modules", home: "/Users/t"))
        #expect(!PathGuard.canRemove("/Users/t", home: "/Users/t"))
    }
}
