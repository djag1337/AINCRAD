import XCTest
@testable import AINCRAD

final class ExtensionTests: XCTestCase {
    func manifest(_ perms: [String]? = nil, sources: [ExtensionManifest.DataSourceDef] = [], id: String = "a.b") -> ExtensionManifest {
        ExtensionManifest(id: id, name: "T", version: "1", apiVersion: 1, permissions: perms,
                          provides: .init(dataSources: sources))
    }

    func testValidationRules() {
        XCTAssertNil(ExtensionManager.validate(manifest()))
        XCTAssertNotNil(ExtensionManager.validate(manifest(id: "../evil")), "id with slashes")
        XCTAssertNotNil(ExtensionManager.validate(manifest(["root"])), "unknown permission")
        let web = ExtensionManifest.DataSourceDef(id: "w", name: "W", url: "https://example.com/x.json")
        XCTAssertNotNil(ExtensionManager.validate(manifest(sources: [web])), "URL without network permission")
        XCTAssertNil(ExtensionManager.validate(manifest(["network"], sources: [web])))
        let ftp = ExtensionManifest.DataSourceDef(id: "f", name: "F", url: "file:///etc/passwd")
        XCTAssertNotNil(ExtensionManager.validate(manifest(["network"], sources: [ftp])), "non-http scheme")
        let both = ExtensionManifest.DataSourceDef(id: "b", name: "B", url: "https://x", file: "y")
        XCTAssertNotNil(ExtensionManager.validate(manifest(["network"], sources: [both])))
        var future = manifest()
        future.apiVersion = 99
        XCTAssertNotNil(ExtensionManager.validate(future))
    }

    func testPathsCannotEscapeTheFolder() {
        let folder = URL(fileURLWithPath: "/tmp/ext")
        XCTAssertNotNil(ExtensionManager.contained("data/x.json", in: folder))
        XCTAssertNil(ExtensionManager.contained("../other/x.json", in: folder))
        XCTAssertNil(ExtensionManager.contained("a/../../x", in: folder))
    }

    func testSampleExtraction() {
        let def = ExtensionManifest.DataSourceDef(id: "t", name: "T", file: "x", value: "current.temps.1", text: "{value}°C", max: 40)
        let s = ExtensionManager.sample(from: Data(#"{"current": {"temps": [10, 20.5]}}"#.utf8), def: def)!
        XCTAssertEqual(s.text, "20.5°C")
        XCTAssertEqual(s.fraction!, 20.5 / 40, accuracy: 0.0001)
        let plain = ExtensionManifest.DataSourceDef(id: "p", name: "P", file: "x")
        XCTAssertEqual(ExtensionManager.sample(from: Data("hello\n".utf8), def: plain)?.text, "hello")
        XCTAssertNil(ExtensionManager.sample(from: Data(#"{"a": 1}"#.utf8),
                                             def: .init(id: "m", name: "M", file: "x", value: "missing")))
    }

    func testExampleLoadsButStaysOffUntilApproved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)
        store.load()
        let mgr = ExtensionManager(store: store)
        _ = try mgr.createExample()
        XCTAssertEqual(mgr.extensions.map(\.id), ["aincrad.example"])
        XCTAssertTrue(mgr.problems.isEmpty, "\(mgr.problems)")
        let ext = mgr.extensions[0]
        XCTAssertFalse(mgr.isEnabled(ext))
        XCTAssertEqual(mgr.menuItems("ext:aincrad.example/links"), [], "disabled extensions contribute nothing")
        XCTAssertTrue(mgr.widgetPresets.isEmpty)
        mgr.setEnabled(ext, true)
        XCTAssertEqual(mgr.menuItems("ext:aincrad.example/links")?.count, 2)
        XCTAssertEqual(mgr.widgetPresets.count, 1)
        XCTAssertNotNil(DataHub.shared.external["ext:aincrad.example/floor"])

        let got = expectation(description: "file source")
        ExtensionManager.fetch(ext.manifest.provides.dataSources![0], folder: ext.folder, filesAllowed: false) { s in
            XCTAssertEqual(s?.text, "Floor 75 / 100")
            got.fulfill()
        }
        wait(for: [got], timeout: 2)
        XCTAssertEqual(try mgr.installThemes(ext), ["aincrad-example-alfheim"])
        XCTAssertEqual(store.loadTheme("aincrad-example-alfheim").colors.accent, "#5FD068")
        mgr.setEnabled(ext, false)
        XCTAssertNil(DataHub.shared.external["ext:aincrad.example/floor"])
    }
}

final class PublisherTests: XCTestCase {
    func sh(_ args: [String], in dir: URL) throws { try Publisher.run("/usr/bin/git", args, in: dir) }

    func testPublishCopiesBuildsCommitsAndPushes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pub-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = root.appendingPathComponent("remote.git"), repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("tools"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try sh(["init", "-q", "--bare"], in: remote)
        try Data("print('built')\n".utf8).write(to: repo.appendingPathComponent("tools/build_catalog.py"))
        try sh(["init", "-q", "-b", "main"], in: repo)
        try sh(["config", "user.email", "t@example.com"], in: repo)
        try sh(["config", "user.name", "T"], in: repo)
        try sh(["add", "-A"], in: repo)
        try sh(["commit", "-q", "-m", "init"], in: repo)
        try sh(["remote", "add", "origin", remote.path], in: repo)
        try sh(["push", "-q", "-u", "origin", "main"], in: repo)

        let ext = root.appendingPathComponent("ext")
        try FileManager.default.createDirectory(at: ext, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: ext.appendingPathComponent("extension.json"))
        var lines: [String] = []
        _ = try Publisher.publish(.extensionFolder(ext, id: "t.ext", name: "T", version: "1.0"), repo: repo) { lines.append($0) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.appendingPathComponent("src/extensions/t.ext/extension.json").path))
        XCTAssertTrue(lines.contains("built"), "\(lines)")
        let log = try Publisher.run("/usr/bin/git", ["log", "--oneline", "-1"], in: remote)
        XCTAssertTrue(log.contains("Publish T 1.0"), log)

        // Publishing the same thing again changes nothing and doesn't fail.
        lines = []
        _ = try Publisher.publish(.extensionFolder(ext, id: "t.ext", name: "T", version: "1.0"), repo: repo) { lines.append($0) }
        XCTAssertTrue(lines.contains { $0.contains("nothing changed") }, "\(lines)")
    }

    func testMissingRepoIsAClearError() {
        XCTAssertThrowsError(try Publisher.publish(.theme(.classic, id: "x"), repo: URL(fileURLWithPath: "/nonexistent"), log: { _ in })) {
            XCTAssertTrue($0.localizedDescription.contains("No catalog repository"))
        }
    }
}

final class BundledPluginTests: XCTestCase {
    /// Every plugin shipped inside the app must pass the same validation as a user's extension.
    func testBundledPluginsValidate() throws {
        let root = try XCTUnwrap(Bundle.main.url(forResource: "Plugins", withExtension: nil), "Plugins folder missing from the app")
        let dirs = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertGreaterThanOrEqual(dirs.count, 16)
        var ids = Set<String>()
        for dir in dirs {
            let m = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: dir.appendingPathComponent("extension.json")))
            XCTAssertNil(ExtensionManager.validate(m), "\(dir.lastPathComponent)")
            XCTAssertTrue(ids.insert(m.id).inserted, "duplicate id \(m.id)")
            XCTAssertTrue(m.permissions?.isEmpty ?? true, "\(m.id) should need no permissions")
            for theme in m.provides.themes ?? [] {
                XCTAssertNoThrow(try TolerantJSON.decode(Theme.self, from: Data(contentsOf: dir.appendingPathComponent(theme)), defaults: .classic), "\(m.id): \(theme)")
            }
        }
    }
}
