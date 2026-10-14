import AppKit

// MARK: Dock

/// SAO dock: the launcher's own glass buttons on a slim rail, with hover lift, accent ring,
/// the app's name above it, running dots, and a divider before running-only apps.
final class ShellDockView: ShellLayerView {
    private(set) var apps: [ShellApp] = []
    private var running = Set<String>(), frontmost: String?
    private var theme = Theme.classic
    private var slots: [CGRect] = []
    private var buttons: [CALayer] = []
    private var rings: [CALayer] = []
    private let rail = CAGradientLayer(), railLine = CALayer(), label = CATextLayer(), labelBack = CALayer()
    private var hovered: Int?
    private var tracking: NSTrackingArea?
    var onClick: ((ShellApp) -> Void)?
    /// Right-click on an app: the app and its button's frame in screen coordinates.
    var onContext: ((ShellApp, NSRect) -> Void)?

    static let size: CGFloat = 50, gap: CGFloat = 10, pad: CGFloat = 14, labelRoom: CGFloat = 34

    static func width(for apps: [ShellApp]) -> CGFloat {
        let dividers = CGFloat(apps.indices.filter { divides(apps, $0) }.count) * 14
        return pad * 2 + CGFloat(apps.count) * size + CGFloat(max(apps.count - 1, 0)) * gap + dividers
    }

    /// A divider goes between pinned and running-only apps.
    static func divides(_ apps: [ShellApp], _ i: Int) -> Bool {
        i > 0 && !apps[i].pinned && apps[i - 1].pinned
    }

    func set(apps: [ShellApp], running: Set<String>, frontmost: String?, theme: Theme) {
        self.apps = apps
        self.running = running
        self.frontmost = frontmost
        self.theme = theme
        rebuild()
    }

    private func rebuild() {
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        buttons = []; rings = []; slots = []
        let c = theme.colors
        let accent = themeColor(c.accent), panel = themeColor(c.panel)
        let w = bounds.width, railTop = ShellDockView.labelRoom, railH = bounds.height - railTop - 4
        Motion.instant {
            rail.frame = CGRect(x: 0, y: railTop, width: w, height: railH)
            rail.cornerRadius = railH / 2
            rail.colors = [panel.withAlphaComponent(0.9).cgColor, (panel.blended(withFraction: 0.1, of: .black) ?? panel).withAlphaComponent(0.9).cgColor]
            rail.borderWidth = theme.effects.borderWidth
            rail.borderColor = themeColor(c.panelBorder).withAlphaComponent(0.6).cgColor
            rail.shadowColor = themeColor(c.shadow).cgColor
            rail.shadowOpacity = Float(theme.effects.shadowOpacity)
            rail.shadowRadius = theme.effects.shadowRadius
            rail.shadowOffset = CGSize(width: 0, height: 2)
            rail.shadowPath = CGPath(roundedRect: rail.bounds, cornerWidth: railH / 2, cornerHeight: railH / 2, transform: nil)
            host.addSublayer(rail)
            railLine.frame = CGRect(x: railH / 2 + 6, y: railTop, width: w - railH - 12, height: 1.5)
            railLine.backgroundColor = accent.cgColor
            railLine.shadowColor = accent.cgColor
            railLine.shadowOpacity = 0.9
            railLine.shadowRadius = 3
            railLine.shadowOffset = .zero
            host.addSublayer(railLine)

            var x = ShellDockView.pad
            let s = ShellDockView.size, cy = railTop + railH / 2
            for (i, app) in apps.enumerated() {
                if ShellDockView.divides(apps, i) {
                    let divider = CALayer()
                    divider.frame = CGRect(x: x + 1, y: cy - 16, width: 1.5, height: 32)
                    divider.backgroundColor = themeColor(c.panelText).withAlphaComponent(0.3).cgColor
                    host.addSublayer(divider)
                    x += 14
                }
                let r = CGRect(x: x, y: cy - s / 2, width: s, height: s)
                slots.append(r)
                let b = CAGradientLayer()
                b.frame = r
                b.cornerRadius = s / 2
                let circle = themeColor(c.circle)
                b.colors = [(circle.blended(withFraction: 0.08, of: .white) ?? circle).cgColor, (circle.blended(withFraction: 0.08, of: .black) ?? circle).cgColor]
                b.borderWidth = 1
                b.borderColor = themeColor(c.circleBorder).cgColor
                b.shadowColor = themeColor(c.shadow).cgColor
                b.shadowOpacity = 0.35
                b.shadowRadius = 4
                b.shadowOffset = CGSize(width: 0, height: 2)
                b.shadowPath = CGPath(ellipseIn: b.bounds, transform: nil)
                let icon = CALayer()
                icon.frame = b.bounds.insetBy(dx: 9, dy: 9)
                icon.contents = IconCache.shared.image("app:" + app.url.path, size: icon.bounds.width, tint: nil, scale: window?.backingScaleFactor ?? 2)
                b.addSublayer(icon)
                let ring = CALayer()
                ring.frame = r.insetBy(dx: -4, dy: -4)
                ring.cornerRadius = (s + 8) / 2
                ring.borderWidth = 2
                ring.borderColor = accent.cgColor
                ring.shadowColor = accent.cgColor
                ring.shadowOpacity = 0.8
                ring.shadowRadius = 6
                ring.shadowOffset = .zero
                ring.opacity = app.bundleID == frontmost ? 0.45 : 0
                host.addSublayer(ring)
                host.addSublayer(b)
                buttons.append(b)
                rings.append(ring)
                if let id = app.bundleID, running.contains(id) {
                    let dot = CALayer()
                    dot.frame = CGRect(x: r.midX - 2.5, y: r.maxY + 3, width: 5, height: 5)
                    dot.cornerRadius = 2.5
                    dot.backgroundColor = accent.cgColor
                    host.addSublayer(dot)
                }
                x += s + ShellDockView.gap
            }
            labelBack.backgroundColor = panel.withAlphaComponent(0.95).cgColor
            labelBack.borderWidth = 1
            labelBack.borderColor = accent.cgColor
            labelBack.cornerRadius = 4
            labelBack.opacity = 0
            host.addSublayer(labelBack)
            let f = ThemeFonts.display(theme, 11)
            label.font = f
            label.fontSize = f.pointSize
            label.foregroundColor = themeColor(c.panelText).cgColor
            label.alignmentMode = .center
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.opacity = 0
            host.addSublayer(label)
        }
        hovered = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    private func index(_ event: NSEvent) -> Int? {
        let p = convert(event.locationInWindow, from: nil)
        return slots.firstIndex { $0.insetBy(dx: -4, dy: -6).contains(p) }
    }

    override func mouseMoved(with event: NSEvent) { setHover(index(event)) }
    override func mouseExited(with event: NSEvent) { setHover(nil) }

    private func setHover(_ i: Int?) {
        guard i != hovered else { return }
        hovered = i
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        for (j, b) in buttons.enumerated() {
            let lifted = j == i
            b.transform = lifted ? CATransform3DMakeTranslation(0, -6, 0) : CATransform3DIdentity
            rings[j].transform = b.transform
            rings[j].opacity = lifted ? 1 : (apps[j].bundleID == frontmost ? 0.45 : 0)
        }
        if let i {
            label.string = apps[i].name.uppercased()
            let tw = min(label.preferredFrameSize().width + 18, 240), r = slots[i]
            let x = min(max(r.midX - tw / 2, 2), bounds.width - tw - 2)
            labelBack.frame = CGRect(x: x, y: 4, width: tw, height: 22)
            label.frame = CGRect(x: x, y: 8, width: tw, height: 16)
            label.opacity = 1
            labelBack.opacity = 1
        } else {
            label.opacity = 0
            labelBack.opacity = 0
        }
        CATransaction.commit()
        if i != nil { SoundPlayer.shared.play(.hover) }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let i = index(event), let window else { return }
        SoundPlayer.shared.play(.select)
        onContext?(apps[i], window.convertToScreen(convert(slots[i], to: nil)))
    }

    override func mouseDown(with event: NSEvent) {
        guard let i = index(event) else { return }
        let b = buttons[i]
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.88
        pulse.toValue = 1
        pulse.duration = 0.18
        b.add(pulse, forKey: "pulse")
        SoundPlayer.shared.play(.select)
        onClick?(apps[i])
    }
}
