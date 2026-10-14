import AppKit

// MARK: Top bar

/// Full-width SAO bar over the menu bar: player block and active app on the left, status and
/// clock on the right. The centre stays empty for notch islands (Alcove, boringNotch, real notches).
final class ShellBarView: ShellLayerView {
    private var theme = Theme.classic
    private let name = CATextLayer(), level = CATextLayer(), appName = CATextLayer(), status = CATextLayer(), clock = CATextLayer()
    private let hpTrack = CAShapeLayer(), hpFill = CALayer(), hpHolder = CALayer(), appIcon = CALayer()
    private let accentLine = CALayer(), backing = CAGradientLayer()
    private let caps = [CAShapeLayer(), CAShapeLayer()]
    var onClick: (() -> Void)?
    /// The player block was clicked; its frame in screen coordinates.
    var onMenus: ((NSRect) -> Void)?
    /// Right-click on the bar outside the player block; a small rect at the click, in screen coordinates.
    var onExtras: ((NSRect) -> Void)?
    private let menuHint = CAShapeLayer(), nameBack = CALayer()
    private var playerRect = CGRect.zero
    private var tracking: NSTrackingArea?

    func build(theme: Theme) {
        self.theme = theme
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        let c = theme.colors
        let panel = themeColor(c.panel), text = themeColor(c.panelText), accent = themeColor(c.accent)
        backing.colors = [panel.withAlphaComponent(0.97).cgColor, (panel.blended(withFraction: 0.08, of: .black) ?? panel).withAlphaComponent(0.97).cgColor]
        host.addSublayer(backing)
        accentLine.backgroundColor = accent.cgColor
        accentLine.shadowColor = accent.cgColor
        accentLine.shadowOpacity = 0.9
        accentLine.shadowRadius = 4
        accentLine.shadowOffset = .zero
        host.addSublayer(accentLine)
        for cap in caps {
            cap.strokeColor = accent.cgColor
            cap.fillColor = nil
            cap.lineWidth = 2
            cap.lineJoin = .miter
            host.addSublayer(cap)
        }
        let display = ThemeFonts.display(theme, 12), body = ThemeFonts.body(theme, 15)
        for (layer, font, color) in [(name, display, text), (level, ThemeFonts.display(theme, 10), text.withAlphaComponent(0.75)),
                                     (appName, display, text), (status, body, text.withAlphaComponent(0.85)), (clock, display, text)] {
            layer.font = font
            layer.fontSize = font.pointSize
            layer.foregroundColor = color.cgColor
            layer.truncationMode = .end
            layer.contentsScale = window?.backingScaleFactor ?? 2
            host.addSublayer(layer)
        }
        status.alignmentMode = .right
        clock.alignmentMode = .right
        hpTrack.fillColor = text.withAlphaComponent(0.12).cgColor
        hpTrack.strokeColor = text.withAlphaComponent(0.55).cgColor
        hpTrack.lineWidth = 1
        host.addSublayer(hpTrack)
        hpHolder.mask = CAShapeLayer()
        hpHolder.addSublayer(hpFill)
        host.addSublayer(hpHolder)
        appIcon.contentsGravity = .resizeAspect
        host.addSublayer(appIcon)
        // The player block opens the app's menus: a hover plate and a small ▾ say so.
        nameBack.backgroundColor = accent.withAlphaComponent(0.18).cgColor
        nameBack.borderColor = accent.cgColor
        nameBack.borderWidth = 1
        nameBack.cornerRadius = 3
        nameBack.opacity = 0
        host.insertSublayer(nameBack, above: backing)
        menuHint.fillColor = accent.cgColor
        host.addSublayer(menuHint)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        Motion.instant {
            backing.frame = bounds
            accentLine.frame = CGRect(x: 36, y: h - 2, width: w - 72, height: 2)
            for (i, cap) in caps.enumerated() {
                let right = i == 1, x: CGFloat = right ? w - 10 : 10, d: CGFloat = right ? -1 : 1
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x + d * 16, y: 6))
                p.addLine(to: CGPoint(x: x, y: 6))
                p.addLine(to: CGPoint(x: x, y: h - 6))
                p.addLine(to: CGPoint(x: x + d * 16, y: h - 6))
                cap.path = p
            }
            let mid = h / 2
            name.frame = CGRect(x: 30, y: mid - 8, width: 150, height: 16)
            let barX: CGFloat = 30 + min(150, (name.preferredFrameSize().width)) + 12, barW: CGFloat = 120, barH: CGFloat = 8
            let shape = CGMutablePath()
            shape.move(to: .zero)
            shape.addLine(to: CGPoint(x: barW, y: 0))
            shape.addLine(to: CGPoint(x: barW - 5, y: barH))
            shape.addLine(to: CGPoint(x: 0, y: barH))
            shape.closeSubpath()
            hpTrack.path = shape
            hpTrack.frame = CGRect(x: barX, y: mid - barH / 2, width: barW, height: barH)
            hpHolder.frame = hpTrack.frame
            (hpHolder.mask as? CAShapeLayer)?.path = shape
            level.frame = CGRect(x: barX + barW + 8, y: mid - 6, width: 50, height: 13)
            playerRect = CGRect(x: 22, y: 3, width: barX + barW + 58 + 14 - 22, height: h - 7)
            nameBack.frame = playerRect
            let hint = CGMutablePath(), hx = playerRect.maxX - 12
            hint.move(to: CGPoint(x: hx, y: mid - 2))
            hint.addLine(to: CGPoint(x: hx + 7, y: mid - 2))
            hint.addLine(to: CGPoint(x: hx + 3.5, y: mid + 2.5))
            hint.closeSubpath()
            menuHint.path = hint
            let appX = barX + barW + 64 + 14
            appIcon.frame = CGRect(x: appX, y: mid - 9, width: 18, height: 18)
            appName.frame = CGRect(x: appX + 24, y: mid - 8, width: min(260, w * 0.5 - appX - 150), height: 16)
            clock.frame = CGRect(x: w - 30 - 240, y: mid - 8, width: 240, height: 16)
            status.frame = CGRect(x: w - 30 - 240 - 20 - 260, y: mid - 9, width: 260, height: 18)
        }
    }

    func update(player: String, hp: Double, lv: Int, app: String, icon: NSImage?, status s: String, clock c: String) {
        Motion.instant {
            name.string = player.uppercased()
            level.string = "LV \(lv)"
            let fillW = 120 * CGFloat(min(max(hp, 0), 1))
            hpFill.frame = CGRect(x: 0, y: 0, width: fillW, height: 8)
            hpFill.backgroundColor = (hp > 0.5 ? HPBarContent.green : hp > 0.2 ? HPBarContent.yellow : HPBarContent.red).cgColor
            appName.string = app.uppercased()
            appIcon.contents = icon.flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
            status.string = s
            clock.string = c.uppercased()
        }
        needsLayout = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        let on = playerRect.contains(convert(event.locationInWindow, from: nil))
        guard (nameBack.opacity == 1) != on else { return }
        nameBack.opacity = on ? 1 : 0
        if on { SoundPlayer.shared.play(.hover) }
    }

    override func mouseExited(with event: NSEvent) { nameBack.opacity = 0 }

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let window else { return }
        if playerRect.contains(p) {
            onMenus?(window.convertToScreen(convert(playerRect, to: nil)))
            return
        }
        SoundPlayer.shared.play(.select)
        onExtras?(window.convertToScreen(convert(CGRect(x: p.x, y: 0, width: 1, height: bounds.height), to: nil)))
    }

    override func mouseDown(with event: NSEvent) {
        if playerRect.contains(convert(event.locationInWindow, from: nil)), let window {
            SoundPlayer.shared.play(.select)
            onMenus?(window.convertToScreen(convert(playerRect, to: nil)))
            return
        }
        onClick?()
    }
}
