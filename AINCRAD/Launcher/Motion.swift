import QuartzCore

/// The one place animation timing is decided. Everything runs on Core Animation's render
/// server clock, so nothing ticks on the main thread while the launcher is hidden.
struct Motion {
    var spec: Theme.Animation
    var reduced: Bool

    static let easeOut = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)

    func duration(_ base: Double) -> CFTimeInterval {
        reduced ? min(base, 0.08) : base / max(spec.speed, 0.1)
    }

    func delay(_ base: Double) -> CFTimeInterval {
        reduced ? 0 : base / max(spec.speed, 0.1)
    }

    /// Fade (and, unless reduced, slide) a freshly built layer into its model position.
    func enter(_ layer: CALayer, offset: CGPoint, delay base: Double, duration d: Double) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = layer.opacity
        var animations: [CAAnimation] = [fade]
        if !reduced && offset != .zero {
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: CGPoint(x: layer.position.x + offset.x, y: layer.position.y + offset.y))
            move.toValue = NSValue(point: layer.position)
            animations.append(move)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration(d)
        group.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay(base)
        group.fillMode = .backwards
        group.timingFunction = Motion.easeOut
        layer.add(group, forKey: "enter")
    }

    /// Model changes inside `body` animate implicitly with this duration.
    func animate(_ base: Double, _ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration(base))
        CATransaction.setAnimationTimingFunction(Motion.easeOut)
        body()
        CATransaction.commit()
    }

    static func instant(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
