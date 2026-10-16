import Foundation
import Testing
@testable import MacSweepCore

@Suite struct FileNodeTests {
    let tree = Fixtures.dir("/Users/test", [
        Fixtures.dir("/Users/test/.npm", [Fixtures.file("/Users/test/.npm/a", size: 300)]),
        Fixtures.dir("/Users/test/Desktop", [
            Fixtures.dir("/Users/test/Desktop/app", [Fixtures.file("/Users/test/Desktop/app/big", size: 500)]),
            Fixtures.file("/Users/test/Desktop/notes.txt", size: 200),
        ]),
    ])

    @Test func findsNestedNodes() {
        #expect(tree.node(at: "/Users/test/Desktop/app/big")?.size == 500)
        #expect(tree.node(at: "/Users/test")?.size == 1000)
    }

    @Test func missingPathReturnsNil() {
        #expect(tree.node(at: "/Users/test/Nope") == nil)
        #expect(tree.node(at: "/Users/other") == nil)
        #expect(tree.node(at: "") == nil)
    }

    @Test func prefixSiblingIsNotMatched() {
        #expect(tree.node(at: "/Users/test/Desktop/apple") == nil)
    }

    @Test func removingUpdatesAncestorSizes() {
        let updated = tree.removing(["/Users/test/Desktop/app"])
        #expect(updated.size == 500)
        #expect(updated.node(at: "/Users/test/Desktop")?.size == 200)
        #expect(updated.node(at: "/Users/test/Desktop/app") == nil)
        #expect(updated.children.first?.path == "/Users/test/.npm")
    }

    @Test func removingEmptySetIsIdentity() {
        #expect(tree.removing([]) == tree)
    }

    @Test func removingUnknownPathChangesNothing() {
        #expect(tree.removing(["/elsewhere/x"]).size == 1000)
    }

    @Test func walkCanSkipSubtrees() {
        var visited: [String] = []
        tree.walk { node in
            visited.append(node.name)
            return node.name != "Desktop"
        }
        #expect(visited.contains("Desktop"))
        #expect(!visited.contains("app"))
        #expect(visited.contains("a"))
    }

    @Test func pathToolsExpandAndAbbreviate() {
        #expect(PathTools.expand("~/.npm", home: "/Users/test") == "/Users/test/.npm")
        #expect(PathTools.expand("~", home: "/Users/test") == "/Users/test")
        #expect(PathTools.expand("/etc", home: "/Users/test") == "/etc")
        #expect(PathTools.abbreviate("/Users/test/x", home: "/Users/test") == "~/x")
        #expect(PathTools.abbreviate("/Users/testing", home: "/Users/test") == "/Users/testing")
    }

    @Test func hiddenComponentDetection() {
        #expect(PathTools.hasHiddenComponent("/Users/test/.cache/x/y", below: "/Users/test"))
        #expect(!PathTools.hasHiddenComponent("/Users/test/Desktop/y", below: "/Users/test"))
    }
}

@Suite struct FileNodeNameTests {
    @Test func namesDeriveFromPathUnlessCustom() {
        #expect(Fixtures.dir("/a/b/proj").name == "proj")
        #expect(FileNode(path: "/a", name: "7 smaller items", kind: .aggregate, size: 1).name == "7 smaller items")
        #expect(FileNode(path: "/", name: "Macintosh HD", kind: .directory, size: 1).name == "Macintosh HD")
        #expect(FileNode(path: "/x/y", name: "", kind: .file, size: 1).name == "y")
    }

    @Test func codableRoundTripKeepsNamesCompact() throws {
        let tree = Fixtures.dir("/r", [Fixtures.file("/r/f", size: 1), FileNode(path: "/r", name: "2 smaller items", kind: .aggregate, size: 2)])
        let data = try PropertyListEncoder().encode(tree)
        let decoded = try PropertyListDecoder().decode(FileNode.self, from: data)
        #expect(decoded == tree)
        #expect(decoded.children.map(\.name).sorted() == ["2 smaller items", "f"])
    }
}
