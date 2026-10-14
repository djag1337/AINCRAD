import Foundation

/// Pure logic for "N fingers swipe in a direction" on a multitouch surface (Magic Mouse or
/// trackpad). Positions are normalised 0…1; y grows away from the user, so "down" (towards
/// you, like SAO's swipe) is decreasing y. Fires once per touch; lifting re-arms it.
struct TouchGestureRecognizer {
    struct Touch { var id: Int32; var x: Float; var y: Float }

    struct Config {
        var fingers = 2
        /// Fraction of the surface height the fingers must travel.
        var distance: Float = 0.22
        var maxTime: Double = 0.8
        var direction = "down"
    }

    var config: Config
    private var start: [Int32: (x: Float, y: Float)] = [:]
    private var startTime: Double = 0
    private var fired = false
    /// Last movement measured, for the log (helps tune direction and distance).
    private(set) var lastTravel: (dx: Float, dy: Float) = (0, 0)

    init(config: Config) { self.config = config }

    /// Feed one frame of touching fingers; returns true when the gesture completes.
    mutating func frame(_ touches: [Touch], time: Double) -> Bool {
        if touches.isEmpty {
            start = [:]
            fired = false
            return false
        }
        guard touches.count == config.fingers else {
            // A different finger count cancels a gesture in progress (but doesn't re-arm).
            start = [:]
            return false
        }
        if start.isEmpty || Set(start.keys) != Set(touches.map(\.id)) {
            start = Dictionary(uniqueKeysWithValues: touches.map { ($0.id, ($0.x, $0.y)) })
            startTime = time
            return false
        }
        guard !fired else { return false }
        var dx: Float = 0, dy: Float = 0
        for t in touches {
            guard let s = start[t.id] else { continue }
            dx += t.x - s.x
            dy += t.y - s.y
        }
        dx /= Float(touches.count)
        dy /= Float(touches.count)
        lastTravel = (dx, dy)
        guard time - startTime <= config.maxTime else { return false }
        let d = config.distance
        let ok: Bool
        switch config.direction {
        case "up": ok = dy >= d && abs(dx) < dy
        case "left": ok = -dx >= d && abs(dy) < -dx
        case "right": ok = dx >= d && abs(dy) < dx
        default: ok = -dy >= d && abs(dx) < -dy
        }
        if ok { fired = true }
        return ok
    }
}
