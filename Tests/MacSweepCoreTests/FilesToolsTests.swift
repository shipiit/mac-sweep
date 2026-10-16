import Foundation
import Testing
@testable import MacSweepCore

@Suite struct FilesToolsTests {
    @Test func listsAndEmptiesTrashBins() throws {
        let root = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let home = root + "/home"
        try Fixtures.write(home + "/.Trash/old.dmg", bytes: 4096)
        try Fixtures.write(home + "/.Trash/folder/x", bytes: 4096)
        try Fixtures.write(root + "/Volumes/USB/.Trashes/501/photo.jpg", bytes: 4096)
        try Fixtures.write(root + "/Volumes/Empty/readme", bytes: 10)

        let bins = TrashBins.list(home: home, volumesRoot: root + "/Volumes", uid: 501)
        #expect(bins.map(\.name) == ["Mac Trash", "USB"])
        #expect(bins[0].itemCount == 2 && bins[0].size > 0)

        let result = TrashBins.empty(bins[0])
        #expect(result.removed == 2 && result.failed.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: home + "/.Trash").isEmpty)
        #expect(FileManager.default.fileExists(atPath: home + "/.Trash"))
    }

    @Test func emptiesLockedItems() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/.Trash/locked.txt", bytes: 10)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: home + "/.Trash/locked.txt")
        let bin = try #require(TrashBins.list(home: home, volumesRoot: home + "/none").first)
        #expect(TrashBins.empty(bin).removed == 1)
    }

    @Test func findsMailStorage() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/A/report.pdf", bytes: 8192)
        try Fixtures.write(home + "/Library/Mail/V10/acct/INBOX.mbox/Data/Attachments/1/file.zip", bytes: 8192)
        let items = MailAttachments.scan(home: home)
        #expect(Set(items.map(\.kind)) == [.downloads, .cachedAttachments])
        #expect(MailAttachments.scan(home: home + "/nobody").isEmpty)
    }

    @Test func shredderDeletesLockedFilesButRespectsGuard() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try Fixtures.write(home + "/Desktop/secret/notes.txt", bytes: 10)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: home + "/Desktop/secret/notes.txt")
        try Fixtures.write(home + "/.ssh/id_rsa", bytes: 10)
        let outcomes = Shredder.shred([home + "/Desktop/secret", home + "/.ssh/id_rsa"], home: home)
        #expect(outcomes[0].error == nil)
        #expect(!FileManager.default.fileExists(atPath: home + "/Desktop/secret"))
        #expect(outcomes[1].error != nil)
        #expect(FileManager.default.fileExists(atPath: home + "/.ssh/id_rsa"))
    }
}
