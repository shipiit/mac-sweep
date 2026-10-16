import Foundation
import Testing
@testable import MacSweepCore

@Suite struct RuntimeInventoryTests {
    private func makeDir(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private func writePackage(_ dir: String, name: String, version: String) throws {
        try makeDir(dir)
        try Data(#"{"name":"\#(name)","version":"\#(version)"}"#.utf8).write(to: URL(fileURLWithPath: dir + "/package.json"))
    }

    @Test func listsVersionsAcrossManagers() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try makeDir(home + "/.nvm/versions/node/v9.12.0")
        try makeDir(home + "/.nvm/versions/node/v20.1.0")
        try makeDir(home + "/.nvm/versions/node/.cache")
        try makeDir(home + "/.pyenv/versions/3.11.4")
        try makeDir(home + "/.pyenv/versions/myenv")
        try makeDir(home + "/.local/share/uv/python/cpython-3.12.4-macos-aarch64-none")
        try makeDir(home + "/.rbenv/versions/3.3.0")
        try Data().write(to: URL(fileURLWithPath: home + "/.rbenv/versions/9.9.9"))

        let versions = RuntimeInventory.versions(home: home)
        #expect(versions.filter { $0.manager == "nvm" }.map(\.version) == ["v20.1.0", "v9.12.0"])
        #expect(versions.filter { $0.manager == "pyenv" }.map(\.version) == ["3.11.4"])
        #expect(versions.first { $0.manager == "uv" }?.version == "cpython 3.12.4")
        #expect(versions.filter { $0.language == .ruby }.map(\.version) == ["3.3.0"])
        #expect(versions.allSatisfy { $0.size == nil })
    }

    @Test func emptyHomeHasNoVersions() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        #expect(RuntimeInventory.versions(home: home).isEmpty)
        #expect(RuntimeInventory.pnpmGlobalRoots(home: home).isEmpty)
    }

    @Test func versionHelpers() {
        #expect(RuntimeInventory.isVersionFolder("v18.0.0"))
        #expect(!RuntimeInventory.isVersionFolder("default"))
        #expect(!RuntimeInventory.isVersionFolder(".DS_Store"))
        #expect(RuntimeInventory.displayVersion("pypy-3.10.14-macos") == "pypy 3.10.14")
        #expect(RuntimeInventory.displayVersion("3.12.1") == "3.12.1")
        #expect(RuntimeInventory.displayVersion("") == "")
        #expect(RuntimeInventory.compareVersions("v20.1.0", "v9.12.0"))
        #expect(!RuntimeInventory.compareVersions("3.9", "3.10"))
        #expect(RuntimeInventory.compareVersions("3.10.1", "3.10"))
        #expect(!RuntimeInventory.compareVersions("same", "same"))
    }

    @Test func readsGlobalPackagesIncludingScoped() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let node = home + "/.nvm/versions/node/v20.1.0"
        try writePackage(node + "/lib/node_modules/typescript", name: "typescript", version: "5.4.0")
        try writePackage(node + "/lib/node_modules/@angular/cli", name: "@angular/cli", version: "17.0.0")
        try writePackage(node + "/lib/node_modules/npm", name: "npm", version: "10.0.0")
        try makeDir(node + "/lib/node_modules/broken")
        try writePackage(home + "/Library/pnpm/global/5/node_modules/vercel", name: "vercel", version: "33.0.0")

        let versions = RuntimeInventory.versions(home: home)
        let packages = RuntimeInventory.allGlobalPackages(home: home, versions: versions)
        let mine = packages.filter { $0.path.hasPrefix(home) }
        #expect(mine.filter { $0.manager == "npm (v20.1.0)" }.map(\.name) == ["@angular/cli", "typescript"])
        #expect(mine.filter { $0.manager == "pnpm" }.map(\.name) == ["vercel"])
        #expect(!mine.contains { $0.name == "npm" })
        #expect(RuntimeInventory.globalPackages(root: home + "/missing", manager: "npm").isEmpty)
    }

    @Test func packageJSONParsing() {
        #expect(RuntimeInventory.parsePackageJSON(Data(#"{"name":"a","version":"1"}"#.utf8))?.version == "1")
        #expect(RuntimeInventory.parsePackageJSON(Data(#"{"name":"a"}"#.utf8))?.version == "")
        #expect(RuntimeInventory.parsePackageJSON(Data(#"{"name":""}"#.utf8)) == nil)
        #expect(RuntimeInventory.parsePackageJSON(Data("[]".utf8)) == nil)
        #expect(RuntimeInventory.parsePackageJSON(Data()) == nil)
    }

    @Test func managerNames() {
        #expect(RuntimeInventory.npmManagerName(root: "/opt/homebrew/lib/node_modules", home: "/Users/t") == "npm (system)")
        #expect(RuntimeInventory.npmManagerName(root: "/Users/t/.nvm/versions/node/v18.0.0/lib/node_modules", home: "/Users/t") == "npm (v18.0.0)")
    }
}

@Suite struct XcodeStorageTests {
    let simctl = """
    {"devices":{
      "com.apple.CoreSimulator.SimRuntime.iOS-26-5":[
        {"lastBootedAt":"2026-07-06T16:18:56Z","dataPathSize":2996690944,"udid":"A","isAvailable":true,"state":"Shutdown","name":"iPhone 17 Pro"},
        {"udid":"B","isAvailable":false,"state":"Booted","name":"iPad","dataPathSize":100}
      ],
      "com.apple.CoreSimulator.SimRuntime.watchOS-11-0":[{"udid":"C","name":"Watch"}],
      "com.apple.CoreSimulator.SimRuntime.tvOS-18-0":[{"name":"missing udid"}]
    }}
    """

    @Test func parsesSimulators() {
        let sims = XcodeStorage.parseSimulators(simctl)
        #expect(sims.map(\.udid) == ["B", "A", "C"])
        let pro = sims.first { $0.udid == "A" }
        #expect(pro?.runtime == "iOS 26.5" && pro?.dataSize == 2_996_690_944 && pro?.lastBooted != nil && pro?.isAvailable == true)
        #expect(sims.first { $0.udid == "B" }?.isBooted == true)
        #expect(sims.first { $0.udid == "B" }?.isAvailable == false)
        #expect(sims.first { $0.udid == "C" }?.isAvailable == true)
    }

    @Test func simulatorGarbage() {
        #expect(XcodeStorage.parseSimulators("").isEmpty)
        #expect(XcodeStorage.parseSimulators("{}").isEmpty)
        #expect(XcodeStorage.parseSimulators(#"{"devices":[]}"#).isEmpty)
        #expect(XcodeStorage.parseSimulators("xcrun: error: unable to find utility").isEmpty)
    }

    @Test func runtimeNames() {
        #expect(XcodeStorage.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-17-0") == "iOS 17.0")
        #expect(XcodeStorage.runtimeName("com.apple.CoreSimulator.SimRuntime.xrOS-2-1") == "xrOS 2.1")
        #expect(XcodeStorage.runtimeName("plain") == "plain")
        #expect(XcodeStorage.runtimeName("") == "")
    }

    @Test func locationsAndChildrenAreTrashableThroughPathGuard() throws {
        let home = try Fixtures.makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: home) }
        let locations = XcodeStorage.locations(home: home)
        #expect(Set(locations.map(\.id)).count == locations.count)
        let derived = try #require(locations.first { $0.id == "derived" })
        try Fixtures.write(derived.path + "/App-abc/Build/x.o", bytes: 10)
        try Fixtures.write(derived.path + "/.hidden", bytes: 1)
        let children = XcodeStorage.children(of: derived.path)
        #expect(children == [derived.path + "/App-abc"])
        #expect(PathGuard.canRemove(children[0], home: home))
        #expect(!PathGuard.canRemove(home + "/Library/Developer", home: home))
        #expect(XcodeStorage.children(of: home + "/nope").isEmpty)
        let results = Cleaner.remove(children.map { CleanupTarget(path: $0, size: 10) }, mode: .delete, home: home)
        #expect(results.allSatisfy { $0.succeeded })
        #expect(FileManager.default.fileExists(atPath: derived.path))
    }
}
