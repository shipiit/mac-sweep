import Foundation
import Testing
@testable import MacSweepCore

@Suite struct ScanGrowthTests {
    static let mb: UInt64 = 1_000_000
    let mb = ScanGrowthTests.mb

    func scan(_ root: FileNode, at seconds: TimeInterval = 0) -> ScanResult {
        ScanResult(root: root, largeFiles: [], restrictedCount: 0, duration: 1,
                   finishedAt: Date(timeIntervalSince1970: 1_800_000_000 + seconds))
    }

    func compare(_ old: FileNode, _ new: FileNode, minimum: UInt64 = 50_000_000, limit: Int = 25) -> ScanGrowthReport? {
        ScanGrowth.compare(old: scan(old), new: scan(new, at: 86_400), minimumDelta: minimum, limit: limit)
    }

    func dir(_ path: String, _ children: [FileNode]) -> FileNode { Fixtures.dir(path, children) }
    func file(_ path: String, _ megabytes: UInt64) -> FileNode { Fixtures.file(path, size: megabytes * mb) }

    @Test func attributesGrowthToTheDeepestExplainingItem() throws {
        let old = dir("/r", [dir("/r/a", [file("/r/a/vm.img", 100), file("/r/a/small", 1)])])
        let new = dir("/r", [dir("/r/a", [file("/r/a/vm.img", 400), file("/r/a/small", 1)])])
        let report = try #require(compare(old, new))
        #expect(report.grown.map(\.path) == ["/r/a/vm.img"])
        #expect(report.grown.first?.delta == 300_000_000)
        #expect(report.grown.first?.change == .grew)
        #expect(report.grown.first?.isDirectory == false)
        #expect(report.shrunk.isEmpty)
        #expect(report.totalDelta == 300_000_000)
        #expect(report.oldDate < report.newDate)
    }

    @Test func folderIsReportedWhenGrowthIsSpreadOut() throws {
        let names = (0..<5).map { "/r/cache/f\($0)" }
        let old = dir("/r", [dir("/r/cache", names.map { file($0, 10) })])
        let new = dir("/r", [dir("/r/cache", names.map { file($0, 30) })])
        let report = try #require(compare(old, new))
        #expect(report.grown.map(\.path) == ["/r/cache"])
        #expect(report.grown.first?.isDirectory == true)
        #expect(report.grown.first?.delta == 100_000_000)
    }

    @Test func addedAndRemovedItems() throws {
        let old = dir("/r", [dir("/r/old", [file("/r/old/x", 200)]), file("/r/keep", 5)])
        let new = dir("/r", [dir("/r/new", [file("/r/new/y", 300), file("/r/new/z", 1)]), file("/r/keep", 5)])
        let report = try #require(compare(old, new))
        #expect(report.grown.map(\.path) == ["/r/new"])
        #expect(report.grown.first?.change == .added)
        #expect(report.grown.first?.oldSize == 0)
        #expect(report.shrunk.map(\.path) == ["/r/old"])
        #expect(report.shrunk.first?.change == .removed)
        #expect(report.shrunk.first?.delta == -200_000_000)
        #expect(report.renamed.isEmpty)
    }

    @Test func renamedFolderIsNotGrowth() throws {
        let old = dir("/r", [dir("/r/photos", [file("/r/photos/a", 300), file("/r/photos/b", 100)])])
        let new = dir("/r", [dir("/r/pictures", [file("/r/pictures/a", 300), file("/r/pictures/b", 100)])])
        let report = try #require(compare(old, new))
        #expect(report.grown.isEmpty)
        #expect(report.shrunk.isEmpty)
        #expect(report.renamed.map(\.path) == ["/r/pictures"])
        #expect(report.renamed.first?.change == .renamed(from: "/r/photos"))
    }

    @Test func differentContentsAreNotARename() throws {
        let old = dir("/r", [dir("/r/a", [file("/r/a/x", 300)])])
        let new = dir("/r", [dir("/r/b", [file("/r/b/x", 400)])])
        let report = try #require(compare(old, new))
        #expect(report.renamed.isEmpty)
        #expect(report.grown.first?.change == .added)
        #expect(report.shrunk.first?.change == .removed)
    }

    @Test func itemsFoldedIntoAggregateTilesAreNotReportedAsAdded() throws {
        let oldTile = FileNode(path: "/r/p", name: "40 smaller items", kind: .aggregate, size: 100 * mb, itemCount: 40)
        let newTile = FileNode(path: "/r/p", name: "39 smaller items", kind: .aggregate, size: 10 * mb, itemCount: 39)
        let old = dir("/r", [dir("/r/p", [file("/r/p/big", 500), oldTile])])
        let new = dir("/r", [dir("/r/p", [file("/r/p/big", 500), file("/r/p/x", 90), newTile])])
        let report = try #require(compare(old, new))
        #expect(report.grown.isEmpty)
        #expect(report.shrunk.isEmpty)
    }

    @Test func growthNextToAnAggregateIsCreditedToTheParent() throws {
        let tile = FileNode(path: "/r/p", name: "5 smaller items", kind: .aggregate, size: 5 * mb, itemCount: 5)
        let old = dir("/r", [dir("/r/p", [file("/r/p/big", 500), tile])])
        let new = dir("/r", [dir("/r/p", [file("/r/p/big", 500), file("/r/p/new", 200), tile])])
        let report = try #require(compare(old, new))
        #expect(report.grown.map(\.path) == ["/r/p"])
        #expect(report.grown.first?.change == .grew)
    }

    @Test func restrictedFoldersAreIgnored() throws {
        let locked = FileNode(path: "/r/a/locked", name: "locked", kind: .restricted, size: 0)
        let old = dir("/r", [dir("/r/a", [locked, file("/r/a/f", 10)])])
        let new = dir("/r", [dir("/r/a", [dir("/r/a/locked", [file("/r/a/locked/huge", 50_000)]), file("/r/a/f", 10)])])
        let report = try #require(compare(old, new))
        #expect(report.grown.isEmpty, "granting Full Disk Access is not growth")
    }

    @Test func changesBelowTheMinimumAreIgnored() throws {
        let old = dir("/r", [dir("/r/a", [file("/r/a/f", 100)])])
        let new = dir("/r", [dir("/r/a", [file("/r/a/f", 149)])])
        #expect(try #require(compare(old, new)).grown.isEmpty)
        #expect(try #require(compare(old, new, minimum: 49 * mb)).grown.map(\.path) == ["/r/a/f"])
    }

    @Test func identicalScansHaveNoChanges() throws {
        let tree = dir("/r", [dir("/r/a", [file("/r/a/f", 100)])])
        let report = try #require(compare(tree, tree))
        #expect(report.grown.isEmpty && report.shrunk.isEmpty && report.renamed.isEmpty)
        #expect(report.totalDelta == 0)
    }

    @Test func sortsAndLimits() throws {
        let old = dir("/r", (0..<5).map { file("/r/f\($0)", 100) })
        let new = dir("/r", (0..<5).map { file("/r/f\($0)", 100 + UInt64($0 + 1) * 100) })
        let report = try #require(compare(old, new, limit: 3))
        #expect(report.grown.map(\.path) == ["/r/f4", "/r/f3", "/r/f2"])
    }

    @Test func shrinkSortsMostNegativeFirst() throws {
        let old = dir("/r", [file("/r/a", 500), file("/r/b", 900)])
        let new = dir("/r", [file("/r/a", 300), file("/r/b", 100)])
        let report = try #require(compare(old, new))
        #expect(report.shrunk.map(\.path) == ["/r/b", "/r/a"])
        #expect(report.shrunk.allSatisfy { $0.change == .shrank })
    }

    @Test func comparesASubfolderOfTheOldScan() throws {
        let old = dir("/r", [dir("/r/a", [file("/r/a/f", 100)]), file("/r/g", 1)])
        let new = dir("/r/a", [file("/r/a/f", 400)])
        let report = try #require(compare(old, new))
        #expect(report.rootPath == "/r/a")
        #expect(report.grown.map(\.path) == ["/r/a/f"])
    }

    @Test func unrelatedRootsCannotBeCompared() {
        let old = dir("/r", [file("/r/f", 1)])
        let new = dir("/other", [file("/other/f", 1)])
        #expect(compare(old, new) == nil)
        #expect(compare(file("/r", 1), file("/r", 2)) == nil)
    }
}
