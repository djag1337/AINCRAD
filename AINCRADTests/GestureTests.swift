import XCTest
@testable import AINCRAD

final class GestureTests: XCTestCase {
    typealias G = GestureRecognizer
    let p = CGPoint(x: 500, y: 400)

    func ev(_ k: G.Kind, _ dx: CGFloat = 0, _ dy: CGFloat = 0, t: Double) -> G.Event {
        G.Event(kind: k, location: CGPoint(x: p.x + dx, y: p.y + dy), time: t)
    }

    func testPlainLeftClickPassesUntouched() {
        var g = G(config: .init())
        XCTAssertEqual(g.handle(ev(.leftDown, t: 0)), .pass)
        XCTAssertEqual(g.handle(ev(.leftDrag, 30, 30, t: 0.1)), .pass)
        XCTAssertEqual(g.handle(ev(.leftUp, t: 0.2)), .pass)
        XCTAssertTrue(g.isIdle)
    }

    func testQuickRightClickIsReplayedOnRelease() {
        var g = G(config: .init())
        XCTAssertEqual(g.handle(ev(.rightDown, t: 0)), .swallow)
        XCTAssertEqual(g.handle(ev(.rightUp, t: 0.05)), G.Decision(deliver: false, replay: [.heldRightDown, .current]))
        XCTAssertTrue(g.isIdle)
    }

    func testHeldRightClickIsReplayedAfterWindow() {
        var g = G(config: .init())
        _ = g.handle(ev(.rightDown, t: 0))
        XCTAssertEqual(g.timeout(now: 0.05), [], "too early")
        XCTAssertEqual(g.timeout(now: 0.09), [.heldRightDown])
        XCTAssertTrue(g.isIdle)
        XCTAssertEqual(g.handle(ev(.rightUp, t: 0.5)), .pass, "release of a replayed press passes")
    }

    func testRightDragBeforeWindowReplays() {
        var g = G(config: .init())
        _ = g.handle(ev(.rightDown, t: 0))
        XCTAssertEqual(g.handle(ev(.rightDrag, 2, 2, t: 0.02)), .pass, "small jitter keeps waiting")
        XCTAssertEqual(g.handle(ev(.rightDrag, 10, 0, t: 0.03)), G.Decision(deliver: false, replay: [.heldRightDown, .current]))
    }

    func testRightThenLeftChordSlideDownFires() {
        var g = G(config: .init())
        _ = g.handle(ev(.rightDown, t: 0))
        XCTAssertEqual(g.handle(ev(.leftDown, t: 0.04)), .swallow)
        XCTAssertEqual(g.handle(ev(.leftDrag, 0, 20, t: 0.1)), .swallow)
        XCTAssertEqual(g.handle(ev(.leftDrag, 3, 45, t: 0.2)), G.Decision(deliver: false, trigger: p))
        XCTAssertEqual(g.handle(ev(.leftDrag, 3, 90, t: 0.3)), .swallow, "fires once")
        XCTAssertEqual(g.handle(ev(.leftUp, t: 0.4)), .swallow, "left press was never delivered")
        XCTAssertEqual(g.handle(ev(.rightUp, t: 0.45)), .swallow)
        XCTAssertTrue(g.isIdle)
    }

    func testLeftThenRightChordDeliversLeftRelease() {
        var g = G(config: .init())
        XCTAssertEqual(g.handle(ev(.leftDown, t: 0)), .pass)
        XCTAssertEqual(g.handle(ev(.rightDown, 1, 1, t: 0.1)), .swallow)
        XCTAssertEqual(g.handle(ev(.rightDrag, 0, 50, t: 0.2)).trigger, p)
        XCTAssertEqual(g.handle(ev(.rightUp, t: 0.3)), .swallow)
        XCTAssertEqual(g.handle(ev(.leftUp, t: 0.35)), .pass, "the app saw the left press, so it gets the release")
        XCTAssertTrue(g.isIdle)
    }

    func testRightClickDuringLongLeftDragIsNotAChord() {
        var g = G(config: .init())
        _ = g.handle(ev(.leftDown, t: 0))
        XCTAssertEqual(g.handle(ev(.rightDown, t: 2.0)), .swallow)
        XCTAssertTrue(g.isPending, "treated as an ordinary (delayed) right click")
    }

    func testWrongDirectionAndSlowSlideDoNotFire() {
        var g = G(config: .init())
        _ = g.handle(ev(.rightDown, t: 0))
        _ = g.handle(ev(.leftDown, t: 0.02))
        XCTAssertNil(g.handle(ev(.leftDrag, 0, -60, t: 0.1)).trigger, "up instead of down")
        XCTAssertNil(g.handle(ev(.leftDrag, 80, 50, t: 0.2)).trigger, "mostly sideways")
        XCTAssertNil(g.handle(ev(.leftDrag, 0, 80, t: 1.5)).trigger, "too slow")
    }

    func testOtherDirectionsAndNone() {
        for (dir, dx, dy) in [("up", 0.0, -50.0), ("left", -50.0, 0.0), ("right", 50.0, 0.0), ("any", 30.0, 30.0)] {
            var g = G(config: .init(slide: dir))
            _ = g.handle(ev(.rightDown, t: 0))
            _ = g.handle(ev(.leftDown, t: 0.01))
            XCTAssertEqual(g.handle(ev(.leftDrag, CGFloat(dx), CGFloat(dy), t: 0.1)).trigger, p, dir)
        }
        var g = G(config: .init(slide: "none"))
        _ = g.handle(ev(.rightDown, t: 0))
        XCTAssertEqual(g.handle(ev(.leftDown, t: 0.01)).trigger, p, "none fires on the chord itself")
        XCTAssertNil(g.handle(ev(.leftDrag, 0, 100, t: 0.1)).trigger)
    }
}

final class RightButtonAndTouchTests: XCTestCase {
    typealias G = GestureRecognizer
    let p = CGPoint(x: 500, y: 400)
    func ev(_ k: G.Kind, _ dx: CGFloat = 0, _ dy: CGFloat = 0, t: Double) -> G.Event {
        G.Event(kind: k, location: CGPoint(x: p.x + dx, y: p.y + dy), time: t)
    }

    func testRightSlideDownFiresAndSwallowsTheRest() {
        var g = G(config: .init(buttons: "right"))
        XCTAssertEqual(g.handle(ev(.rightDown, t: 0)), .swallow)
        XCTAssertEqual(g.handle(ev(.rightDrag, 1, 15, t: 0.1)), .swallow, "sliding down: keep waiting")
        XCTAssertEqual(g.handle(ev(.rightDrag, 2, 45, t: 0.2)).trigger, p)
        XCTAssertEqual(g.handle(ev(.rightDrag, 2, 80, t: 0.3)), .swallow)
        XCTAssertEqual(g.handle(ev(.rightUp, t: 0.4)), .swallow, "the app never saw the press")
        XCTAssertTrue(g.isIdle)
    }

    func testRightClickAndSidewaysDragStayNormal() {
        var g = G(config: .init(buttons: "right"))
        _ = g.handle(ev(.rightDown, t: 0))
        XCTAssertEqual(g.handle(ev(.rightUp, t: 0.08)), G.Decision(deliver: false, replay: [.heldRightDown, .current]))
        _ = g.handle(ev(.rightDown, t: 1))
        XCTAssertEqual(g.handle(ev(.rightDrag, 30, 2, t: 1.1)), G.Decision(deliver: false, replay: [.heldRightDown, .current]),
                       "dragging sideways is an ordinary right-drag")
    }

    func testRightHoldWithoutMovingBecomesNormalPressSoon() {
        var g = G(config: .init(buttons: "right"))
        _ = g.handle(ev(.rightDown, t: 0))
        XCTAssertEqual(g.timeout(now: 0.2), [])
        XCTAssertEqual(g.timeout(now: 0.31), [.heldRightDown], "press-and-hold context menus still appear")
    }

    func testRightModeIgnoresLeftChord() {
        var g = G(config: .init(buttons: "right"))
        _ = g.handle(ev(.leftDown, t: 0))
        XCTAssertEqual(g.handle(ev(.rightDown, t: 0.05)), .swallow)
        XCTAssertTrue(g.isPending)
    }

    // Touch
    typealias T = TouchGestureRecognizer
    func two(_ y: Float, _ x: Float = 0.5) -> [T.Touch] { [T.Touch(id: 1, x: x, y: y), T.Touch(id: 2, x: x + 0.2, y: y)] }

    func testTwoFingerSwipeDownFiresOnce() {
        var t = T(config: .init())
        XCTAssertFalse(t.frame(two(0.8), time: 0))
        XCTAssertFalse(t.frame(two(0.7), time: 0.1))
        XCTAssertTrue(t.frame(two(0.5), time: 0.2))
        XCTAssertFalse(t.frame(two(0.3), time: 0.3), "once per touch")
        XCTAssertFalse(t.frame([], time: 0.4))
        XCTAssertFalse(t.frame(two(0.8), time: 1))
        XCTAssertTrue(t.frame(two(0.5), time: 1.2), "lifting re-arms")
    }

    func testOneFingerScrollUpwardsAndSlowSwipesDontFire() {
        var t = T(config: .init())
        _ = t.frame([T.Touch(id: 1, x: 0.5, y: 0.8)], time: 0)
        XCTAssertFalse(t.frame([T.Touch(id: 1, x: 0.5, y: 0.2)], time: 0.1), "one finger is scrolling")
        _ = t.frame([], time: 0.2)
        _ = t.frame(two(0.3), time: 1)
        XCTAssertFalse(t.frame(two(0.8), time: 1.1), "upwards")
        _ = t.frame([], time: 2)
        _ = t.frame(two(0.8), time: 3)
        XCTAssertFalse(t.frame(two(0.4), time: 4.5), "too slow")
    }
}
