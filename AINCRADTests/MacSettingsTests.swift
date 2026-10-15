import XCTest
@testable import AINCRAD

/// Read-only: nothing here writes a preference.
final class MacSettingsTests: XCTestCase {
    func testTableIsWellFormed() {
        let ids = MacSettings.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "unique ids")
        let sections = Set(MacSettings.sections.map(\.id)).union(["appearance"])
        for s in MacSettings.all {
            XCTAssertTrue(sections.contains(s.section), "\(s.id) section \(s.section)")
            if case .choice(let options, let def) = s.kind {
                XCTAssertTrue(options.indices.contains(def), s.id)
                XCTAssertTrue(options.indices.contains(MacSettings.choiceIndex(s)), "\(s.id) reads a valid choice")
            } else {
                _ = MacSettings.isOn(s)   // reads without crashing
            }
        }
    }

    func testEverySectionBuilds() {
        let app = AppSettings()
        for section in MacSettings.sections.map(\.id) + ["appearance"] {
            XCTAssertFalse(MacSettings.items(section: section, settings: app).isEmpty, section)
        }
        XCTAssertEqual(MacSettings.choiceItems("dock-position").map(\.name), ["Left", "Bottom", "Right"])
        XCTAssertGreaterThan(MacSettings.pageItems().count, 30)
    }

    func testManagedSettingsLockWhenAINCRADHidesTheDock() {
        var app = AppSettings()
        app.hideAppleDock = true
        let dock = MacSettings.items(section: "dock", settings: app).first { $0.id == "mac:dock-autohide" }
        XCTAssertNil(dock?.action, "locked while AINCRAD hides the Dock")
        XCTAssertEqual(dock?.icon, "sf:lock.fill")
    }

    func testProfileValuesRoundTrip() throws {
        let values: [CFPropertyList?] = [true as CFBoolean, 48 as CFNumber, 1.5 as CFNumber, "bottom" as CFString, nil]
        for v in values {
            let encoded = try JSONEncoder().encode(Profile.Value(v))
            let back = try JSONDecoder().decode(Profile.Value.self, from: encoded)
            XCTAssertEqual(back, Profile.Value(v))
        }
        XCTAssertEqual(Profile.Value(true as CFBoolean), .bool(true))
        XCTAssertEqual(Profile.Value(48 as CFNumber), .int(48))
    }

    func testCurrentProfileCapturesTheBasics() {
        let p = Profiles.current(named: "Test", app: AppSettings())
        XCTAssertEqual(p.name, "Test")
        XCTAssertNotNil(p.dark)
        XCTAssertFalse(p.mac.isEmpty)
    }
}
