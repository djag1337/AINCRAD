import AppKit

/// The SAO heads-up frame that bursts out from the menu to the screen edges while the
/// launcher is open: corner brackets, edge rules, a player bar (name, HP, LV) and a clock.
/// Built only when the launcher opens; nothing exists or animates while it's closed.
final class HUDLayer {
    let layer = CALayer()
    private var corners: [CAShapeLayer] = []
    private var edges: [CALayer] = []
    private let status = CALayer()
    private let footer = CATextLayer()

    struct Stats {
        var name: String
        var hp: Double        // 0…1
        var hpText: String
        var level: Int
    }

    func present(in bounds: CGRect, from origin: CGRect, theme: Theme, motion: Motion, scale: CGFloat, stats: Stats, showStatus: Bool = true) {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        corners = []
        edges = []
        let accent = themeColor(theme.colors.accent)
        let line = NSColor.white.withAlphaComponent(0.75)
        let inset: CGFloat = 18
        let target = bounds.insetBy(dx: inset, dy: inset)
        let arm: CGFloat = 46

        Motion.instant {
            layer.frame = CGRect(origin: .zero, size: CGSize(width: bounds.maxX, height: bounds.maxY))
            layer.opacity = 1
            // Four corner brackets, travelling from the menu's corners to the screen's.
            for i in 0..<4 {
                let c = CAShapeLayer()
                let p = CGMutablePath()
                let sx: CGFloat = i % 2 == 0 ? 1 : -1, sy: CGFloat = i < 2 ? 1 : -1
                p.move(to: CGPoint(x: 0, y: sy * arm))
                p.addLine(to: .zero)
                p.addLine(to: CGPoint(x: sx * arm, y: 0))
                c.path = p
                c.strokeColor = accent.cgColor
                c.fillColor = nil
                c.lineWidth = 2.5
                c.lineCap = .square
                c.shadowColor = accent.cgColor
                c.shadowOpacity = 0.8
                c.shadowRadius = 6
                c.shadowOffset = .zero
                c.position = HUDLayer.corner(i, of: origin)
                layer.addSublayer(c)
                corners.append(c)
            }
            // Edge rules (top, bottom), growing from the menu's width to the screen's.
            for top in [true, false] {
                let e = CALayer()
                e.backgroundColor = line.cgColor
                e.bounds = CGRect(x: 0, y: 0, width: origin.width, height: 1)
                e.position = CGPoint(x: origin.midX, y: top ? origin.minY : origin.maxY)
                e.opacity = 0.9
                layer.addSublayer(e)
                edges.append(e)
            }
            buildStatus(theme: theme, scale: scale, stats: stats, accent: accent, at: CGPoint(x: target.minX + 28, y: target.minY + 14))
            footer.string = "\(Date().formatted(date: .complete, time: .shortened).uppercased())   ·   AINCRAD"
            footer.font = HUDLayer.font(theme, 13)
            footer.fontSize = 13
            footer.foregroundColor = line.cgColor
            footer.alignmentMode = .center
            footer.contentsScale = scale
            footer.frame = CGRect(x: target.minX, y: target.maxY - 26, width: target.width, height: 18)
            footer.shadowColor = NSColor.black.cgColor
            footer.shadowOpacity = 0.8
            footer.shadowRadius = 3
            footer.shadowOffset = .zero
            if showStatus { layer.addSublayer(footer) } else { status.removeFromSuperlayer() }
            status.opacity = 0
            footer.opacity = 0
        }

        motion.animate(theme.animation.open * 1.2) {
            for (i, c) in corners.enumerated() { c.position = HUDLayer.corner(i, of: target) }
            edges[0].bounds.size.width = target.width - 2 * arm - 20
            edges[0].position = CGPoint(x: target.midX, y: target.minY)
            edges[1].bounds.size.width = target.width - 2 * arm - 20
            edges[1].position = CGPoint(x: target.midX, y: target.maxY)
        }
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = motion.duration(0.25)
        fadeIn.beginTime = CACurrentMediaTime() + motion.delay(theme.animation.open * 0.8)
        fadeIn.fillMode = .backwards
        Motion.instant {
            status.opacity = 1
            footer.opacity = 1
        }
        status.add(fadeIn, forKey: "in")
        footer.add(fadeIn, forKey: "in")
    }

    private func buildStatus(theme: Theme, scale: CGFloat, stats: Stats, accent: NSColor, at p: CGPoint) {
        status.sublayers?.forEach { $0.removeFromSuperlayer() }
        status.frame = CGRect(x: p.x, y: p.y, width: 420, height: 44)
        let backing = CALayer()
        backing.frame = CGRect(x: -10, y: -4, width: 430, height: 46)
        backing.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor
        backing.cornerRadius = 4
        status.addSublayer(backing)
        let f = HUDLayer.font(theme, 19)
        let name = CATextLayer()
        name.string = stats.name
        name.font = f
        name.fontSize = 19
        name.foregroundColor = NSColor.white.cgColor
        name.contentsScale = scale
        name.frame = CGRect(x: 0, y: 4, width: 120, height: 24)
        name.shadowColor = NSColor.black.cgColor
        name.shadowOpacity = 0.8
        name.shadowRadius = 3
        name.shadowOffset = .zero
        status.addSublayer(name)
        // Slanted HP bar, like the anime's.
        let w: CGFloat = 220, h: CGFloat = 14, x: CGFloat = 124, y: CGFloat = 8
        let shape = CGMutablePath()
        shape.move(to: CGPoint(x: 0, y: 0))
        shape.addLine(to: CGPoint(x: w, y: 0))
        shape.addLine(to: CGPoint(x: w - 8, y: h))
        shape.addLine(to: CGPoint(x: 0, y: h))
        shape.closeSubpath()
        let track = CAShapeLayer()
        track.path = shape
        track.frame = CGRect(x: x, y: y, width: w, height: h)
        track.fillColor = NSColor.black.withAlphaComponent(0.4).cgColor
        track.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        track.lineWidth = 1.2
        status.addSublayer(track)
        let holder = CALayer()
        holder.frame = track.frame
        let mask = CAShapeLayer()
        mask.path = shape
        holder.mask = mask
        let fill = CALayer()
        let hp = min(max(stats.hp, 0), 1)
        fill.frame = CGRect(x: 0, y: 2, width: (w - 4) * hp, height: h - 4)
        fill.backgroundColor = (hp > 0.5 ? HPBarContent.green : hp > 0.2 ? HPBarContent.yellow : HPBarContent.red).cgColor
        holder.addSublayer(fill)
        status.addSublayer(holder)
        let small = HUDLayer.font(theme, 12)
        for (text, frame) in [(stats.hpText, CGRect(x: x + w - 120, y: y + h + 3, width: 116, height: 15)),
                              ("LV \(stats.level)", CGRect(x: x + w + 8, y: y - 1, width: 60, height: 17))] {
            let t = CATextLayer()
            t.string = text
            t.font = small
            t.fontSize = 12
            t.foregroundColor = NSColor.white.cgColor
            t.alignmentMode = frame.minX > x + w ? .left : .right
            t.contentsScale = scale
            t.frame = frame
            status.addSublayer(t)
        }
        layer.addSublayer(status)
    }

    func dismiss() {
        layer.opacity = 0
    }

    static func corner(_ i: Int, of r: CGRect) -> CGPoint {
        CGPoint(x: i % 2 == 0 ? r.minX : r.maxX, y: i < 2 ? r.minY : r.maxY)
    }

    static func font(_ theme: Theme, _ size: CGFloat) -> NSFont { ThemeFonts.display(theme, size) }
}
