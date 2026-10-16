import XCTest
@testable import AINCRAD

final class QuickCommandTests: XCTestCase {
    func testEveryCommandNeedingAPermissionIsOffByDefault() {
        let fresh = AppSettings()
        for c in QuickCommands.all where c.permission != nil && !["remind", "event"].contains(c.id) {
            XCTAssertFalse(QuickCommands.isOn(c, fresh), "\(c.id) needs \(c.permission!) and must start off")
        }
        for c in QuickCommands.all where c.permission == nil { XCTAssertTrue(QuickCommands.isOn(c, fresh), c.id) }
    }

    func testOffCommandsSayWhyAndWhere() {
        let rows = QuickCommands.results("message mom on my way", settings: AppSettings())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "message is off")
        XCTAssertTrue(rows[0].description?.contains("Contacts") ?? false)
        if case .builtin(let b)? = rows[0].action { XCTAssertEqual(b, "settings:quickcommands") } else { XCTFail() }
    }

    func testOnCommandsBuildDraftsNotSends() {
        var s = AppSettings()
        s.quickCommands["message"] = true
        let row = QuickCommands.results("message mom on my way", settings: s).first
        XCTAssertEqual(row?.name, "Message mom: on my way")
        XCTAssertTrue(row?.description?.contains("you press Send") ?? false)
    }

    func testMatchingAndHelp() {
        XCTAssertEqual(QuickCommands.match("volume 40")?.0.id, "volume")
        XCTAssertNil(QuickCommands.match("textedit"), "prefixes need a space or an exact match")
        XCTAssertEqual(QuickCommands.results("volume 40", settings: AppSettings()).first?.name, "Set volume to 40%")
        XCTAssertEqual(QuickCommands.results("commands", settings: AppSettings()).count, QuickCommands.all.count)
        XCTAssertEqual(QuickCommands.results("note buy milk", settings: AppSettings()).first?.name, "Note: buy milk")
    }
}

final class ContactCommandTests: XCTestCase {
    func testContactCommandIsOffThenOpensACard() {
        XCTAssertTrue(QuickCommands.results("contact sam", settings: AppSettings()).first?.name.contains("is off") ?? false)
        var s = AppSettings(); s.quickCommands["contact"] = true
        XCTAssertEqual(QuickCommands.results("contact sam", settings: s).first?.name, "Open contact: sam")
    }
}
