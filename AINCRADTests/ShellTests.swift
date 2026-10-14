import XCTest
@testable import AINCRAD

final class ShellTests: XCTestCase {
    private func app(_ name: String, pinned: Bool) -> ShellApp {
        ShellApp(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"), bundleID: "test.\(name)", pinned: pinned)
    }

    func testDividerSitsBetweenPinnedAndRunningOnly() {
        let apps = [app("A", pinned: true), app("B", pinned: true), app("C", pinned: false), app("D", pinned: false)]
        XCTAssertEqual(apps.indices.filter { ShellDockView.divides(apps, $0) }, [2])
        let allPinned = [app("A", pinned: true), app("B", pinned: true)]
        XCTAssertTrue(allPinned.indices.filter { ShellDockView.divides(allPinned, $0) }.isEmpty)
    }

    func testDockWidthCountsButtonsGapsAndDivider() {
        let s = ShellDockView.size, g = ShellDockView.gap, p = ShellDockView.pad
        let two = [app("A", pinned: true), app("B", pinned: true)]
        XCTAssertEqual(ShellDockView.width(for: two), p * 2 + 2 * s + g)
        let mixed = two + [app("C", pinned: false)]
        XCTAssertEqual(ShellDockView.width(for: mixed), p * 2 + 3 * s + 2 * g + 14)
        XCTAssertEqual(ShellDockView.width(for: []), p * 2)
    }

    func testBarHeightIsPositiveOnEveryScreen() {
        for screen in NSScreen.screens { XCTAssertGreaterThan(ShellController.barHeight(for: screen), 0) }
    }

    func testDemoModeIsOffUnlessAsked() {
        XCTAssertFalse(ShellController.demo)
    }

    func testMenuNodeHelpers() {
        var ran = false
        let action = AXMenus.Node.action("Quit") { ran = true }
        XCTAssertFalse(action.separator)
        AXMenus.press(action)
        XCTAssertTrue(ran)
        XCTAssertTrue(AXMenus.Node.separatorLine.separator)
        let sub = AXMenus.Node.submenu("Windows", [action])
        XCTAssertTrue(sub.hasChildren && sub.enabled)
        XCTAssertEqual(AXMenus.children(sub).map(\.title), ["Quit"])
        XCTAssertFalse(AXMenus.Node.submenu("Empty", []).enabled)
    }
}

final class QuestOrderTests: XCTestCase {
    func testOverdueThenTimedThenAllDay() {
        let now = Date()
        typealias Q = QuestStore.Quest
        let later = Q(title: "later", kind: .event, start: now.addingTimeInterval(7200))
        let soon = Q(title: "soon", kind: .event, start: now.addingTimeInterval(600))
        let allDay = Q(title: "allday", kind: .event, start: now.addingTimeInterval(60), allDay: true)
        let overdue = Q(title: "overdue", kind: .reminder, start: now.addingTimeInterval(-86_400), overdue: true)
        let undated = Q(title: "undated", kind: .reminder)
        let order = QuestStore.ordered([later, undated, allDay, soon, overdue]).map(\.title)
        XCTAssertEqual(Array(order.prefix(3)), ["overdue", "soon", "later"])
        XCTAssertEqual(Set(order.suffix(2)), ["allday", "undated"])
    }

    func testCountdownWording() {
        let now = Date()
        XCTAssertEqual(QuestContent.countdown(to: now.addingTimeInterval(-5), now: now), "now")
        XCTAssertEqual(QuestContent.countdown(to: now.addingTimeInterval(25 * 60), now: now), "in 25m")
        XCTAssertEqual(QuestContent.countdown(to: now.addingTimeInterval(120 * 60), now: now), "in 2h")
        XCTAssertEqual(QuestContent.countdown(to: now.addingTimeInterval(95 * 60), now: now), "in 1h 35m")
    }
}
