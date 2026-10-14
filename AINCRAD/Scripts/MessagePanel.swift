import AppKit

/// The SAO "Message" box: a header, a divider and the text, popping in near the top of the
/// display under the pointer. Dismisses itself after a few seconds or on click.
final class MessagePanel {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ text: String, title: String, theme: Theme, reducedMotion: Bool) {
        hideWork?.cancel()
        panel?.orderOut(nil)
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }

        let c = theme.colors
        let titleFont = ThemeFonts.display(theme, 21), bodyFont = ThemeFonts.body(theme, 19)
        let width: CGFloat = min(520, max(340, (text as NSString).size(withAttributes: [.font: bodyFont]).width + 80))
        let bodyHeight = ceil((text as NSString).boundingRect(with: NSSize(width: width - 48, height: 400),
                                                             options: [.usesLineFragmentOrigin], attributes: [.font: bodyFont]).height)
        let height = 70 + bodyHeight + 34
        let margin: CGFloat = 20

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width + margin * 2, height: height + margin * 2),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.ignoresMouseEvents = false
        let view = ClickView { [weak self] in self?.hide(reducedMotion: reducedMotion) }
        let host = CALayer()
        host.isGeometryFlipped = true
        view.layer = host
        view.wantsLayer = true
        p.contentView = view

        let box = CALayer()
        box.frame = CGRect(x: margin, y: margin, width: width, height: height)
        box.backgroundColor = themeColor(c.panel).withAlphaComponent(0.97).cgColor
        box.cornerRadius = theme.geometry.bubbleRadius
        box.borderWidth = 1
        box.borderColor = themeColor(c.panelBorder).cgColor
        box.shadowColor = themeColor(c.shadow).cgColor
        box.shadowOpacity = 0.6
        box.shadowRadius = 14
        box.shadowOffset = CGSize(width: 0, height: 4)
        box.shadowPath = CGPath(roundedRect: box.bounds, cornerWidth: box.cornerRadius, cornerHeight: box.cornerRadius, transform: nil)
        host.addSublayer(box)

        func textLayer(_ s: String, _ f: NSFont, _ frame: CGRect, color: String, wrap: Bool = false) {
            let t = CATextLayer()
            t.string = s
            t.font = f
            t.fontSize = f.pointSize
            t.foregroundColor = themeColor(color).cgColor
            t.alignmentMode = .center
            t.isWrapped = wrap
            t.contentsScale = screen.backingScaleFactor
            t.frame = frame
            box.addSublayer(t)
        }
        textLayer(title, titleFont, CGRect(x: 16, y: 16, width: width - 32, height: 32), color: c.panelText)
        let divider = CALayer()
        divider.frame = CGRect(x: 24, y: 56, width: width - 48, height: 1)
        divider.backgroundColor = themeColor(c.panelText).withAlphaComponent(0.35).cgColor
        box.addSublayer(divider)
        let footer = CALayer()
        footer.frame = CGRect(x: 0, y: 64, width: width, height: height - 64)
        footer.backgroundColor = themeColor(c.infoFooter).cgColor
        footer.cornerRadius = theme.geometry.bubbleRadius
        footer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        box.addSublayer(footer)
        textLayer(text, bodyFont, CGRect(x: 24, y: 64 + 16, width: width - 48, height: bodyHeight + 4), color: c.panelText, wrap: true)
        let accent = CALayer()
        accent.frame = CGRect(x: width / 2 - 30, y: height - 10, width: 60, height: 3)
        accent.backgroundColor = themeColor(c.accent).cgColor
        accent.cornerRadius = 1.5
        box.addSublayer(accent)

        let vf = screen.visibleFrame
        // Top-left, under the shell's top bar: the centre belongs to the menu and the notch.
        p.setFrameOrigin(NSPoint(x: vf.minX + 4, y: vf.maxY - p.frame.height - 16))
        p.orderFrontRegardless()
        panel = p

        if !reducedMotion {
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.6
            pop.toValue = 1
            pop.stiffness = 320
            pop.damping = 22
            pop.duration = pop.settlingDuration
            box.add(pop, forKey: "pop")
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.15
        box.add(fade, forKey: "fade")

        let work = DispatchWorkItem { [weak self] in self?.hide(reducedMotion: reducedMotion) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(3.5, Double(text.count) / 18), execute: work)
    }

    private func hide(reducedMotion: Bool) {
        guard let p = panel else { return }
        panel = nil
        hideWork?.cancel()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reducedMotion ? 0.05 : 0.2
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }

    private final class ClickView: NSView {
        let onClick: () -> Void
        init(_ onClick: @escaping () -> Void) { self.onClick = onClick; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("not used") }
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onClick() }
    }
}
