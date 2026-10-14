import XCTest
@testable import AINCRAD

final class ConfigTests: XCTestCase {
    func testHexParsing() {
        let c = NSColor(hex: "#F2A516")!
        XCTAssertEqual(c.redComponent, 0xF2 / 255, accuracy: 0.001)
        XCTAssertEqual(c.alphaComponent, 1, accuracy: 0.001)
        XCTAssertEqual(NSColor(hex: "00000080")!.alphaComponent, 128 / 255, accuracy: 0.001)
        XCTAssertNil(NSColor(hex: "#12345"))
        XCTAssertNil(NSColor(hex: "#GGGGGG"))
    }

    func testPartialThemeKeepsDefaults() throws {
        let json = ##"{"colors": {"accent": "#FF0000"}, "geometry": {"itemWidth": 300}}"##
        let t = try TolerantJSON.decode(Theme.self, from: Data(json.utf8), defaults: .classic)
        XCTAssertEqual(t.colors.accent, "#FF0000")
        XCTAssertEqual(t.colors.panel, Theme.classic.colors.panel)
        XCTAssertEqual(t.geometry.itemWidth, 300)
        XCTAssertEqual(t.geometry.itemHeight, Theme.classic.geometry.itemHeight)
        XCTAssertEqual(t.animation, Theme.classic.animation)
    }

    func testSettingsWithUnknownAndMissingKeys() throws {
        let json = ##"{"hotKey": {"key": "a", "modifiers": ["command"]}, "futureKey": 1}"##
        let s = try TolerantJSON.decode(AppSettings.self, from: Data(json.utf8), defaults: AppSettings())
        XCTAssertEqual(s.hotKey, HotKeySpec(key: "a", modifiers: ["command"]))
        XCTAssertEqual(s.theme, "aincrad-classic")
    }

    func testMenuItemWithoutIdDecodes() throws {
        let json = ##"{"name": "Safari", "action": {"type": "app", "target": "com.apple.Safari"}}"##
        let item = try JSONDecoder().decode(MenuItem.self, from: Data(json.utf8))
        XCTAssertFalse(item.id.isEmpty)
        XCTAssertEqual(item.action, .app("com.apple.Safari"))
        XCTAssertFalse(item.hasSubmenu)
    }

    func testUnknownActionTypeIsReportedWithPath() {
        let json = ##"{"schemaVersion": 1, "root": [{"name": "X", "action": {"type": "teleport", "target": "x"}}]}"##
        XCTAssertThrowsError(try JSONDecoder().decode(MenuFile.self, from: Data(json.utf8))) { error in
            let message = TolerantJSON.describe(error)
            XCTAssertTrue(message.contains("teleport"), message)
            XCTAssertTrue(message.contains("root"), message)
        }
    }

    func testDefaultMenuRoundTrips() throws {
        let menu = DefaultMenu.build()
        XCTAssertFalse(menu.root.isEmpty)
        let decoded = try JSONDecoder().decode(MenuFile.self, from: TolerantJSON.encode(menu))
        XCTAssertEqual(decoded, menu)
    }

    func testStoreCreatesFilesAndSurvivesBrokenMenu() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)
        store.load()
        XCTAssertTrue(store.problems.isEmpty, "\(store.problems)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.themesURL.appendingPathComponent("aincrad-dark.json").path))

        try Data("{ not json".utf8).write(to: store.menuURL)
        store.load()
        XCTAssertEqual(store.problems.count, 1)
        XCTAssertFalse(store.menu.root.isEmpty, "falls back to the built-in menu")
        XCTAssertEqual(try String(contentsOf: store.menuURL), "{ not json", "the user's broken file is left alone")
    }
}

final class LayoutTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testAnchorFollowsCursorInTheMiddle() {
        let a = MenuLayout.anchor(cursor: CGPoint(x: 900, y: 500), bounds: screen, rootSize: CGSize(width: 54, height: 330), leftReserve: 170, margin: 40)
        XCTAssertEqual(a, CGPoint(x: 900, y: 500))
    }

    func testAnchorClampsAtEdges() {
        let a = MenuLayout.anchor(cursor: CGPoint(x: 2, y: 1079), bounds: screen, rootSize: CGSize(width: 54, height: 330), leftReserve: 170, margin: 40)
        XCTAssertEqual(a.x, 40 + 170 + 27)
        XCTAssertEqual(a.y, 1080 - 40 - 165)
    }

    func testShiftOnlyWhenOverflowing() {
        XCTAssertEqual(MenuLayout.horizontalShift(leftEdge: 300, rightEdge: 1500, bounds: screen, margin: 40), 0)
        XCTAssertEqual(MenuLayout.horizontalShift(leftEdge: 900, rightEdge: 2000, bounds: screen, margin: 40), -120)
        // Never pushes the left edge past the margin.
        XCTAssertEqual(MenuLayout.horizontalShift(leftEdge: 100, rightEdge: 2600, bounds: screen, margin: 40), -60)
    }

    func testRowOpacityFalloff() {
        XCTAssertEqual(MenuLayout.rowOpacity(distance: 0, visibleRows: 6), 1)
        XCTAssertEqual(MenuLayout.rowOpacity(distance: -4, visibleRows: 6), 1)
        XCTAssertLessThan(MenuLayout.rowOpacity(distance: 6, visibleRows: 6), 0.5)
        XCTAssertEqual(MenuLayout.rowOpacity(distance: 7, visibleRows: 6), 0)
    }

    func testHotKeyDisplay() {
        XCTAssertEqual(HotKey.display(HotKeySpec(key: "space", modifiers: ["option", "control"])), "⌃⌥Space")
        XCTAssertEqual(HotKey.display(HotKeySpec(key: "k", modifiers: ["command", "shift"])), "⇧⌘K")
    }
}
