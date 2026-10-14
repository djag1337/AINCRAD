import AppKit

/// A small optional launcher button that stays available while the full launcher is closed.
final class CommandDeckController: NSObject {
    private let productivity: ProductivityCenter
    private let panel: NSPanel
    private var timer: Timer?
    var openLauncher: (() -> Void)?

    private let view = DeckView(frame: NSRect(x: 0, y: 0, width: 46, height: 46))
    var theme = Theme.classic
    /// Room left for the SAO top bar when it replaces the menu bar.
    var topInset: CGFloat = 0

    init(productivity: ProductivityCenter) {
        self.productivity = productivity
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 46, height: 46), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.contentView = view
        view.onClick = { [weak self] in self?.openLauncher?() }
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.maxX - panel.frame.width - 16, y: f.maxY - panel.frame.height - 10 - topInset))
        view.build(theme: theme, scale: screen.backingScaleFactor)
        refresh()
        panel.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func hide() { timer?.invalidate(); timer = nil; panel.orderOut(nil) }

    private func refresh() {
        let parts = [productivity.timerSummary, productivity.latestClipboardTitle.map { "Clipboard: \($0)" }].compactMap { $0 }
        view.toolTip = parts.isEmpty ? "Open AINCRAD" : parts.joined(separator: " · ")
    }

}

/// The deck button in the launcher's own style: a glass circle with an accent ring and an
/// orange SAO target glyph that lights up on hover.
private final class DeckView: NSView {
    private let circle = CAGradientLayer(), ring = CAShapeLayer(), glyph = CAShapeLayer(), dot = CALayer()
    private var tracking: NSTrackingArea?
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func build(theme: Theme, scale: CGFloat) {
        wantsLayer = true
        guard let host = layer else { return }
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        let c = theme.colors, accent = themeColor(c.accent), base = themeColor(c.circle)
        let r = bounds.insetBy(dx: 5, dy: 5)
        Motion.instant {
            circle.frame = r
            circle.cornerRadius = r.width / 2
            circle.colors = [(base.blended(withFraction: 0.08, of: .white) ?? base).cgColor, (base.blended(withFraction: 0.1, of: .black) ?? base).cgColor]
            circle.borderWidth = 1
            circle.borderColor = themeColor(c.circleBorder).cgColor
            circle.shadowColor = themeColor(c.shadow).cgColor
            circle.shadowOpacity = 0.45
            circle.shadowRadius = 4
            circle.shadowOffset = CGSize(width: 0, height: 1.5)
            circle.shadowPath = CGPath(ellipseIn: CGRect(origin: .zero, size: r.size), transform: nil)
            host.addSublayer(circle)
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 2, dy: 2), transform: nil)
            ring.fillColor = nil
            ring.strokeColor = accent.cgColor
            ring.lineWidth = 1.5
            ring.shadowColor = accent.cgColor
            ring.shadowRadius = 4
            ring.shadowOffset = .zero
            ring.shadowOpacity = 0.7
            ring.opacity = 0.35
            host.addSublayer(ring)
            let g = CGMutablePath(), mid = CGPoint(x: bounds.midX, y: bounds.midY)
            g.addEllipse(in: CGRect(x: mid.x - 9, y: mid.y - 9, width: 18, height: 18))
            for (dx, dy) in [(0.0, -1.0), (0.0, 1.0), (-1.0, 0.0), (1.0, 0.0)] {
                g.move(to: CGPoint(x: mid.x + dx * 12, y: mid.y + dy * 12))
                g.addLine(to: CGPoint(x: mid.x + dx * 6, y: mid.y + dy * 6))
            }
            glyph.frame = bounds
            glyph.path = g
            glyph.fillColor = nil
            glyph.strokeColor = accent.cgColor
            glyph.lineWidth = 2
            glyph.lineCap = .round
            host.addSublayer(glyph)
            dot.frame = CGRect(x: mid.x - 2.5, y: mid.y - 2.5, width: 5, height: 5)
            dot.cornerRadius = 2.5
            dot.backgroundColor = accent.cgColor
            host.addSublayer(dot)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }

    private func setHover(_ on: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        ring.opacity = on ? 1 : 0.35
        glyph.transform = on ? CATransform3DMakeRotation(.pi / 4, 0, 0, 1) : CATransform3DIdentity
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.85
        pulse.toValue = 1
        pulse.duration = 0.18
        circle.add(pulse, forKey: "pulse")
        onClick?()
    }
}
