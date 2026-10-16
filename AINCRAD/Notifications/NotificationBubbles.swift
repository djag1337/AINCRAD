import AppKit

/// SAO-style notification bubbles stacked in a corner of the display under the pointer.
/// Each lives in its own small click-through-except-itself panel and leaves after a few seconds.
final class NotificationBubbles {
    private final class Bubble {
        let panel: NSPanel
        var hideWork: DispatchWorkItem?
        /// The display it's stacked on (bubbles stack per display).
        var display: CGDirectDisplayID = 0
        init(panel: NSPanel) { self.panel = panel }
    }

    private var bubbles: [Bubble] = []
    private let width: CGFloat = 340
    private let gap: CGFloat = 10
    var maxVisible = 4
    var seconds: Double = 6

    /// With `cover` (the macOS banner's frame), the bubble is drawn over the banner so only the SAO
    /// one shows; the real notification is left alone and files into Notification Center as usual.
    func show(_ note: NotificationMirror.Note, theme: Theme, reducedMotion: Bool, cover: CGRect? = nil, on target: NSScreen? = nil) {
        let mouse = NSEvent.mouseLocation
        let coverScreen = cover.flatMap { c in NSScreen.screens.first { $0.frame.intersects(c) } }
        guard let screen = target ?? coverScreen ?? NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let width = cover.map { max(self.width, $0.width + 8) } ?? self.width
        let c = theme.colors
        let titleFont = ThemeFonts.display(theme, 15), bodyFont = ThemeFonts.body(theme, 15)
        let textW = width - 84
        // Measured height + slack: a text layer won't draw a line that doesn't fully fit.
        let bodyH = note.body.isEmpty ? 0 : min(66, ceil((note.body as NSString).boundingRect(
            with: NSSize(width: textW - 6, height: 200), options: [.usesLineFragmentOrigin], attributes: [.font: bodyFont]).height) + 8)
        var height = max(64, 22 + 22 + bodyH + (note.app.isEmpty ? 0 : 16) + 6)
        if let cover { height = max(height, cover.height + 8) }
        let margin: CGFloat = 14

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width + margin * 2, height: height + margin * 2),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let bubble = Bubble(panel: panel)
        let view = BubbleView(onClick: { [weak self, weak bubble] in
            if let url = AppScriptHost.appURL(note.app) { NSWorkspace.shared.open(url) }
            if let bubble { self?.dismiss(bubble, reducedMotion: reducedMotion) }
        }, onHover: { [weak self, weak bubble] inside in
            guard let self, let bubble else { return }
            // Hovering keeps a bubble around; leaving restarts its timer.
            if inside { bubble.hideWork?.cancel() } else { self.schedule(bubble, reducedMotion: reducedMotion) }
        })
        let host = CALayer()
        host.isGeometryFlipped = true
        view.layer = host
        view.wantsLayer = true
        panel.contentView = view

        let box = CALayer()
        box.frame = CGRect(x: margin, y: margin, width: width, height: height)
        box.backgroundColor = themeColor(c.panel).withAlphaComponent(0.97).cgColor
        box.cornerRadius = theme.geometry.bubbleRadius
        box.borderWidth = 1
        box.borderColor = themeColor(c.panelBorder).cgColor
        box.shadowColor = themeColor(c.shadow).cgColor
        box.shadowOpacity = 0.55
        box.shadowRadius = 10
        box.shadowOffset = CGSize(width: 0, height: 3)
        box.shadowPath = CGPath(roundedRect: box.bounds, cornerWidth: box.cornerRadius, cornerHeight: box.cornerRadius, transform: nil)
        host.addSublayer(box)
        let accent = CALayer()
        accent.frame = CGRect(x: 0, y: 10, width: 3, height: height - 20)
        accent.backgroundColor = themeColor(c.accent).cgColor
        accent.cornerRadius = 1.5
        box.addSublayer(accent)

        let badge = CALayer()
        badge.frame = CGRect(x: 14, y: 14, width: 44, height: 44)
        badge.cornerRadius = 22
        badge.backgroundColor = themeColor(c.circle).cgColor
        badge.borderWidth = 1.5
        badge.borderColor = themeColor(c.accent).cgColor
        let icon = CALayer()
        icon.frame = badge.bounds.insetBy(dx: 7, dy: 7)
        icon.contentsGravity = .resizeAspect
        let spec = AppScriptHost.appURL(note.app).map { "app:" + $0.path } ?? "sf:bell.fill"
        icon.contents = IconCache.shared.image(spec, size: 30, tint: spec.hasPrefix("sf:") ? themeColor(c.accent) : nil,
                                               scale: screen.backingScaleFactor)
        badge.addSublayer(icon)
        box.addSublayer(badge)

        var y: CGFloat = 12
        func text(_ s: String, _ f: NSFont, _ h: CGFloat, alpha: CGFloat = 1, wrap: Bool = false) {
            let t = CATextLayer()
            t.string = s
            t.font = f
            t.fontSize = f.pointSize
            t.foregroundColor = themeColor(c.panelText).withAlphaComponent(alpha).cgColor
            t.isWrapped = wrap
            // Truncation on a wrapped text layer cuts it to one line; let it wrap and clip.
            t.truncationMode = wrap ? .none : .end
            t.masksToBounds = wrap
            t.contentsScale = screen.backingScaleFactor
            t.frame = CGRect(x: 70, y: y, width: textW, height: h)
            box.addSublayer(t)
            y += h + 2
        }
        if !note.app.isEmpty { text(note.app.uppercased(), HUDLayer.font(theme, 11), 14, alpha: 0.6) }
        text(note.title, titleFont, 22)
        if bodyH > 0 { text(note.body, bodyFont, bodyH + 2, alpha: 0.85, wrap: true) }

        // Newest on top; older ones move down.
        bubble.display = screen.displayID
        bubbles.insert(bubble, at: 0)
        let here = bubbles.filter { $0.display == bubble.display }
        if here.count > maxVisible { here.suffix(from: maxVisible).forEach { dismiss($0, reducedMotion: true) } }
        let vf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: vf.maxX - panel.frame.width - 6, y: vf.maxY - panel.frame.height - 6))
        restack(screen: screen, except: bubble)
        if let cover {
            // Over the banner itself, above Notification Center's windows.
            panel.level = .screenSaver
            panel.setFrameOrigin(NSPoint(x: cover.midX - width / 2 - margin, y: cover.midY - height / 2 - margin))
        }
        panel.orderFrontRegardless()

        if !reducedMotion {
            let slide = CASpringAnimation(keyPath: "position.x")
            slide.fromValue = box.position.x + 60
            slide.toValue = box.position.x
            slide.stiffness = 260
            slide.damping = 22
            slide.duration = slide.settlingDuration
            box.add(slide, forKey: "slide")
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.15
        box.add(fade, forKey: "fade")
        schedule(bubble, reducedMotion: reducedMotion)
    }

    private func restack(screen: NSScreen, except newest: Bubble) {
        let vf = screen.visibleFrame
        var top = vf.maxY - 6
        for b in bubbles where b.display == screen.displayID {
            let f = b.panel.frame
            let origin = NSPoint(x: vf.maxX - f.width - 6, y: top - f.height)
            // Window origins don't animate through the animator proxy; whole frames do.
            let frame = NSRect(origin: origin, size: f.size)
            if b === newest { b.panel.setFrame(frame, display: true) } else { b.panel.animator().setFrame(frame, display: true) }
            top -= f.height - 28 + gap   // panels carry 14 pt of shadow margin on each side
        }
    }

    private func schedule(_ bubble: Bubble, reducedMotion: Bool) {
        bubble.hideWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak bubble] in
            if let bubble { self?.dismiss(bubble, reducedMotion: reducedMotion) }
        }
        bubble.hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func dismiss(_ bubble: Bubble, reducedMotion: Bool) {
        bubble.hideWork?.cancel()
        bubbles.removeAll { $0 === bubble }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reducedMotion ? 0.05 : 0.2
            bubble.panel.animator().alphaValue = 0
        }, completionHandler: { bubble.panel.orderOut(nil) })
        if let screen = NSScreen.screens.first(where: { $0.displayID == bubble.display }),
           let first = bubbles.first(where: { $0.display == bubble.display }) { restack(screen: screen, except: first) }
    }

    private final class BubbleView: NSView {
        let onClick: () -> Void
        let onHover: (Bool) -> Void
        init(onClick: @escaping () -> Void, onHover: @escaping (Bool) -> Void) {
            self.onClick = onClick
            self.onHover = onHover
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onClick() }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }
    }
}
