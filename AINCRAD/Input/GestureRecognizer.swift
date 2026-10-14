import CoreGraphics

/// Pure state machine for the "hold both buttons, then slide" gesture, kept free of event-tap
/// plumbing so every path is unit-testable.
///
/// Rules, chosen so ordinary clicking is never delayed:
/// * Left clicks always pass through immediately.
/// * A right press is held back for `chordWindow`. If the left button joins in time, both are
///   swallowed (a clean chord: the app under the cursor sees nothing). Otherwise the held press
///   is replayed, so a normal right-click arrives `chordWindow` late but intact.
/// * Right pressed while left is already held (pressed recently, barely moved) also forms a
///   chord. The left press was already delivered, so its release is delivered too.
/// * During a chord, drags are swallowed and the slide is measured; crossing `distance` in the
///   configured direction fires once.
struct GestureRecognizer {
    enum Kind { case leftDown, leftUp, leftDrag, rightDown, rightUp, rightDrag }

    struct Event {
        var kind: Kind
        var location: CGPoint
        var time: Double
    }

    enum Replay: Equatable { case heldRightDown, current }

    struct Decision: Equatable {
        var deliver: Bool
        var replay: [Replay] = []
        var trigger: CGPoint? = nil
        static let pass = Decision(deliver: true)
        static let swallow = Decision(deliver: false)
    }

    struct Config {
        /// "both" buttons, or "right" alone (slide while holding the right button).
        var buttons = "both"
        var slide = "down"          // down, up, left, right, any, none
        var distance: CGFloat = 40
        var chordWindow: Double = 0.09
        var maxSlide: Double = 1.2
        /// How recently the left press may have happened for a left-first chord.
        var leftFirstWindow: Double = 0.35
        /// Right-button mode: a press that hasn't started sliding by then is an ordinary right
        /// press (so press-and-hold context menus still appear).
        var holdWindow: Double = 0.3
    }

    var config: Config

    private enum Phase {
        case idle
        case pendingRight(location: CGPoint, time: Double, moving: Bool)
        case chord(start: CGPoint, time: Double, leftDelivered: Bool, left: Bool, right: Bool, fired: Bool)
    }

    private var phase = Phase.idle
    private var leftDownAt: (location: CGPoint, time: Double)?

    init(config: Config) { self.config = config }

    var isIdle: Bool { if case .idle = phase { return true } else { return false } }
    var isPending: Bool { if case .pendingRight = phase { return true } else { return false } }

    mutating func handle(_ e: Event) -> Decision {
        switch phase {
        case .idle:
            switch e.kind {
            case .leftDown:
                leftDownAt = (e.location, e.time)
                return .pass
            case .leftUp:
                leftDownAt = nil
                return .pass
            case .rightDown:
                if config.buttons == "both", let l = leftDownAt, e.time - l.time <= config.leftFirstWindow,
                   distance(l.location, e.location) < 8 {
                    phase = .chord(start: l.location, time: e.time, leftDelivered: true, left: true, right: true, fired: false)
                    return startChord(at: l.location)
                }
                phase = .pendingRight(location: e.location, time: e.time, moving: false)
                return .swallow
            default:
                return .pass
            }

        case .pendingRight(let location, let time, _) where config.buttons == "right":
            return handleRightOnly(e, start: location, time: time)

        case .pendingRight(let location, _, _):
            switch e.kind {
            case .leftDown:
                leftDownAt = nil
                phase = .chord(start: location, time: e.time, leftDelivered: false, left: true, right: true, fired: false)
                return startChord(at: location)
            case .rightUp:
                phase = .idle
                return Decision(deliver: false, replay: [.heldRightDown, .current])
            case .rightDrag where distance(location, e.location) > 6:
                phase = .idle
                return Decision(deliver: false, replay: [.heldRightDown, .current])
            default:
                return .pass
            }

        case .chord(let start, let time, let leftDelivered, var left, var right, var fired):
            var decision = Decision.swallow
            switch e.kind {
            case .leftDrag, .rightDrag:
                if !fired, e.time - time <= config.maxSlide, slideMatches(from: start, to: e.location) {
                    fired = true
                    decision.trigger = start
                }
            case .leftUp:
                left = false
                decision.deliver = leftDelivered
            case .rightUp:
                right = false
            case .leftDown:
                left = true
            case .rightDown:
                right = true
            }
            phase = (left || right) ? .chord(start: start, time: time, leftDelivered: leftDelivered, left: left, right: right, fired: fired) : .idle
            if !left { leftDownAt = nil }
            return decision
        }
    }

    /// Called periodically while a right press is held back; returns a replay once it's clear
    /// the press is an ordinary right click.
    mutating func timeout(now: Double) -> [Replay] {
        guard case .pendingRight(_, let time, let moving) = phase else { return [] }
        let limit = config.buttons == "right" ? (moving ? config.maxSlide : config.holdWindow) : config.chordWindow
        guard now - time >= limit - 0.0005 else { return [] }
        phase = .idle
        return [.heldRightDown]
    }

    /// Right-button mode: sliding in the configured direction opens the launcher; anything else
    /// (release, a sideways or backwards move, a left press) delivers the held right press.
    private mutating func handleRightOnly(_ e: Event, start: CGPoint, time: Double) -> Decision {
        switch e.kind {
        case .rightDrag:
            if slideMatches(from: start, to: e.location) {
                phase = .chord(start: start, time: time, leftDelivered: false, left: false, right: true, fired: true)
                return Decision(deliver: false, trigger: start)
            }
            if deviates(from: start, to: e.location) {
                phase = .idle
                return Decision(deliver: false, replay: [.heldRightDown, .current])
            }
            phase = .pendingRight(location: start, time: time, moving: distance(start, e.location) > 3)
            return .swallow
        case .rightUp, .leftDown:
            phase = .idle
            return Decision(deliver: false, replay: [.heldRightDown, .current])
        default:
            return .pass
        }
    }

    /// Movement that can't be the start of the slide: too far sideways or the wrong way.
    private func deviates(from a: CGPoint, to b: CGPoint) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y
        let along: CGFloat, across: CGFloat
        switch config.slide {
        case "up": along = -dy; across = abs(dx)
        case "left": along = -dx; across = abs(dy)
        case "right": along = dx; across = abs(dy)
        default: along = dy; across = abs(dx)
        }
        return along < -6 || across > max(14, along)
    }

    /// Drops any state, e.g. when the tap is re-enabled after the system disabled it.
    mutating func reset() {
        phase = .idle
        leftDownAt = nil
    }

    private mutating func startChord(at start: CGPoint) -> Decision {
        guard config.slide == "none" else { return .swallow }
        if case .chord(let s, let t, let d, let l, let r, _) = phase {
            phase = .chord(start: s, time: t, leftDelivered: d, left: l, right: r, fired: true)
        }
        return Decision(deliver: false, trigger: start)
    }

    private func slideMatches(from a: CGPoint, to b: CGPoint) -> Bool {
        // CG global coordinates: y grows downward.
        let dx = b.x - a.x, dy = b.y - a.y, d = config.distance
        switch config.slide {
        case "down": return dy >= d && abs(dx) < dy
        case "up": return -dy >= d && abs(dx) < -dy
        case "right": return dx >= d && abs(dy) < dx
        case "left": return -dx >= d && abs(dy) < -dx
        default: return hypot(dx, dy) >= d
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
}
