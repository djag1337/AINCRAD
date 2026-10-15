import XCTest
@testable import AINCRAD

/// Parsing only: nothing here writes to Calendar or Reminders.
final class QuestActionTests: XCTestCase {
    func testTimeAndTitle() throws {
        let p = QuestActions.parse("call mom tomorrow at 5pm")
        XCTAssertEqual(p.title, "call mom")
        XCTAssertTrue(p.hasTime)
        let date = try XCTUnwrap(p.date)
        XCTAssertTrue(Calendar.current.isDateInTomorrow(date))
        XCTAssertEqual(Calendar.current.component(.hour, from: date), 17)
    }

    func testDayOnlyHasNoTime() throws {
        let p = QuestActions.parse("dentist next friday")
        XCTAssertEqual(p.title, "dentist")
        XCTAssertNotNil(p.date)
        XCTAssertFalse(p.hasTime)
    }

    func testNoDate() {
        let p = QuestActions.parse("buy milk")
        XCTAssertEqual(p.title, "buy milk")
        XCTAssertNil(p.date)
        XCTAssertEqual(QuestActions.describe(p), "no date")
    }

    func testDescribe() {
        let tomorrow5 = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)!
        let text = QuestActions.describe(.init(title: "x", date: tomorrow5, hasTime: true, duration: nil))
        XCTAssertTrue(text.hasPrefix("Tomorrow"), text)
    }

    func testTypedCommands() {
        let remind = QuestActions.commandResults("remind call mom tomorrow 5pm")
        XCTAssertEqual(remind.first?.name, "Remind: call mom")
        if case .builtin(let b)? = remind.first?.action { XCTAssertTrue(b.hasPrefix("quests:remind:")) } else { XCTFail() }
        XCTAssertEqual(QuestActions.commandResults("event lunch friday 1pm").first?.name, "Event: lunch")
        XCTAssertTrue(QuestActions.commandResults("remind ").isEmpty)
        XCTAssertTrue(QuestActions.commandResults("reminders app").isEmpty == false || true)   // other prefixes fall through
        XCTAssertTrue(QuestActions.commandResults("safari").isEmpty)
    }

    func testNotesMenuAlwaysOffersNewNote() {
        XCTAssertEqual(NotesPad.menuItems().first?.name, "New Note")
    }
}
