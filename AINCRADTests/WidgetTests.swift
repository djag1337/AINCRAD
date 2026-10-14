import XCTest
@testable import AINCRAD

final class WidgetTests: XCTestCase {
    func testMinimalWidgetDecodesWithDefaults() throws {
        let json = #"{"widgets": [{"type": "clock", "style": {"fontSize": 30}}]}"#
        let l = try JSONDecoder().decode(WidgetLayout.self, from: Data(json.utf8))
        XCTAssertEqual(l.widgets.count, 1)
        XCTAssertEqual(l.widgets[0].width, 240)
        XCTAssertEqual(l.widgets[0].style.fontSize, 30)
        XCTAssertTrue(l.widgets[0].style.showPanel)
        XCTAssertFalse(l.widgets[0].id.isEmpty)
    }

    func testCatalogEntriesRoundTrip() throws {
        let l = WidgetLayout(widgets: WidgetCatalog.entries.map { $0.make() })
        XCTAssertEqual(try JSONDecoder().decode(WidgetLayout.self, from: TolerantJSON.encode(l)), l)
    }

    func testHPRowsParsing() {
        let rows = HPBarContent.parseRows("Kirito:cpu, Asuna : Memory, bad, X:nope, Silica:disk")
        XCTAssertEqual(rows.map(\.0), ["Kirito", "Asuna", "Silica"])
        XCTAssertEqual(rows.map(\.1), [.cpu, .memory, .disk])
    }

    func testDataSourcesReturnSaneValues() {
        let hub = DataHub()
        _ = hub.sample(.cpu)
        let cpu = hub.sample(.cpu)
        XCTAssertNotNil(cpu)
        let mem = hub.sample(.memory)!
        XCTAssertTrue((0...1).contains(mem.fraction!), "\(mem.fraction!)")
        XCTAssertEqual(mem.total, Double(ProcessInfo.processInfo.physicalMemory))
        let disk = hub.sample(.disk)!
        XCTAssertTrue((0...1).contains(disk.fraction!))
        XCTAssertNotNil(hub.sample(.battery))
        XCTAssertNotNil(hub.sample(.uptime)?.used)
    }

    func testSubscriptionStartsAndStopsSource() {
        let hub = DataHub()
        let t = hub.subscribe(.memory) { _ in }
        XCTAssertEqual(hub.activeSources, ["memory"])
        hub.unsubscribe(t)
        XCTAssertTrue(hub.activeSources.isEmpty, "no subscribers, no timer")
    }
}

final class MenuFileTests: XCTestCase {
    func testMenuWithoutSchemaVersionDecodes() throws {
        let m = try JSONDecoder().decode(MenuFile.self, from: Data(#"{"root": [{"name": "A"}]}"#.utf8))
        XCTAssertEqual(m.schemaVersion, 1)
        XCTAssertEqual(m.root.first?.name, "A")
    }
}

final class SearchTests: XCTestCase {
    func testCalculator() {
        XCTAssertEqual(Calculator.evaluate("2+3*4"), 14)
        XCTAssertEqual(Calculator.evaluate("(2+3)*4"), 20)
        XCTAssertEqual(Calculator.evaluate("2^10"), 1024)
        XCTAssertEqual(Calculator.evaluate("-3 + 5"), 2)
        XCTAssertEqual(Calculator.evaluate("10 ÷ 4"), 2.5)
        XCTAssertNil(Calculator.evaluate("1/0"), "no infinity")
        XCTAssertNil(Calculator.evaluate("2+"), "incomplete")
        XCTAssertNil(Calculator.evaluate("42"), "a plain number isn't a calculation")
        XCTAssertNil(Calculator.evaluate("rm -rf"), "only arithmetic characters")
        XCTAssertEqual(Calculator.format(2.5), "2.5")
        XCTAssertEqual(Calculator.format(1024), "1024")
    }

    func testRanking() {
        XCTAssertGreaterThan(SearchEngine.score("Safari", "saf"), SearchEngine.score("Disk Safety", "saf"))
        XCTAssertGreaterThan(SearchEngine.score("Visual Studio Code", "vsc"), 0, "initials")
        XCTAssertEqual(SearchEngine.score("Terminal", "xyz"), 0)
    }

    func testInstantResultsOrderAndWebFallback() {
        let apps = [MenuItem(name: "Safari", action: .app("/Applications/Safari.app")),
                    MenuItem(name: "Steam", action: .app("/Applications/Steam.app"))]
        let r = SearchEngine.instant("saf", apps: apps, menu: [])
        XCTAssertEqual(r.first?.name, "Safari")
        XCTAssertEqual(r.last?.id, "search:web")
        XCTAssertEqual(SearchEngine.instant("12*12", apps: apps, menu: []).first?.name, "= 144")
        XCTAssertTrue(SearchEngine.instant("wifi", apps: [], menu: []).contains { $0.name == "Wi-Fi" })
    }
}

final class GameLibraryTests: XCTestCase {
    func testValveKeyValues() {
        let vdf = """
        "libraryfolders" { "0" { "path"  "/Users/x/Library/Application Support/Steam"  "label" "" }
                           "1" { "path"  "/Volumes/Games/Steam Library" } }
        """
        XCTAssertEqual(GameLibrary.values(for: "path", in: vdf), ["/Users/x/Library/Application Support/Steam", "/Volumes/Games/Steam Library"])
        XCTAssertEqual(GameLibrary.values(for: "name", in: #""appid" "620" "name" "Portal 2""#), ["Portal 2"])
    }

    func testMenuGroupsBySource() {
        let g = [GameLibrary.Game(id: "steam:1", title: "Balatro", source: "Steam", action: .url("steam://rungameid/1")),
                 GameLibrary.Game(id: "prism:a", title: "RUNE Dev", source: "Minecraft", action: .builtin("prism:a"))]
        let m = GameLibrary.menu(g)
        XCTAssertEqual(m.map(\.name), ["All Games", "Steam", "Minecraft"])
        XCTAssertEqual(m[0].children?.count, 2)
        XCTAssertTrue(GameLibrary.menu([]).isEmpty)
    }
}

final class HUDWidgetTests: XCTestCase {
    func testHUDFlagDefaultsOffAndRoundTrips() throws {
        let plain = try JSONDecoder().decode(WidgetConfig.self, from: Data(#"{"type":"clock"}"#.utf8))
        XCTAssertFalse(plain.hud)
        var w = plain
        w.hud = true
        let back = try JSONDecoder().decode(WidgetConfig.self, from: JSONEncoder().encode(w))
        XCTAssertTrue(back.hud)
    }

    func testStarterFitsInsideTheHUD() {
        let size = CGSize(width: 1920, height: 1080)
        let starter = WidgetCatalog.hudStarter(display: "", size: size)
        XCTAssertFalse(starter.isEmpty)
        for w in starter {
            XCTAssertTrue(w.hud)
            // Inside the brackets (18 pt) and clear of the top bar and the SAO dock.
            XCTAssertGreaterThanOrEqual(w.x, 40)
            XCTAssertLessThanOrEqual(w.x + w.width, Double(size.width) - 40)
            XCTAssertGreaterThanOrEqual(w.y, 40)
            XCTAssertLessThanOrEqual(w.y + w.height, Double(size.height) - Double(ShellController.dockHeight))
        }
    }
}
