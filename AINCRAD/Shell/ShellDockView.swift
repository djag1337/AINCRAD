import AppKit

// MARK: Dock

/// SAO dock: the launcher's own glass buttons on a slim rail, with hover lift, accent ring,
/// the app's name above it, running dots, and a divider before running-only apps.
/// Edited in place: drag a pinned item to reorder it or off the dock to remove it, and drop
/// apps or folders from Finder onto it.
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
    /// A folder was clicked; its button's frame in screen coordinates.
    var onFolder: ((ShellApp, NSRect) -> Void)?
    /// Drag edits, by index among the pinned items.
    var onMove: ((Int, Int) -> Void)?
    var onRemove: ((ShellApp) -> Void)?
    /// Files dropped from Finder, and the pinned index to insert them at.
    var onDrop: (([URL], Int) -> Void)?

    private var press: (index: Int, start: CGPoint)?
    private var dragging = false
    private var dropTarget: Int?
    private let marker = CALayer()

    static let size: CGFloat = 50, gap: CGFloat = 10, pad: CGFloat = 14, labelRoom: CGFloat = 34

    static func width(for apps: [ShellApp]) -> CGFloat {
        let dividers = CGFloat(apps.indices.filter { divides(apps, $0) }.count) * 14
        return pad * 2 + CGFloat(apps.count) * size + CGFloat(max(apps.count - 1, 0)) * gap + dividers
    }

    /// A divider goes between pinned and running-only apps.
    static func divides(_ apps: [ShellApp], _ i: Int) -> Bool {
        i > 0 && !apps[i].pinned && apps[i - 1].pinned
    }

    private var builtSize = CGSize.zero

    func set(apps: [ShellApp], running: Set<String>, frontmost: String?, theme: Theme) {
        // Opening the launcher calls this every time; only redraw when something changed.
        let relevant = Set(apps.compactMap(\.bundleID)).intersection(running)
        if apps == self.apps, relevant == Set(self.apps.compactMap(\.bundleID)).intersection(self.running),
           frontmost == self.frontmost, theme == self.theme, bounds.size == builtSize, !buttons.isEmpty { return }
        builtSize = bounds.size
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
                let spec = app.themedIcon ? "themedfolder:" + c.accent : "app:" + app.url.path
                icon.contents = IconCache.shared.image(spec, size: icon.bounds.width, tint: nil, scale: window?.backingScaleFactor ?? 2)
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
                if !app.folder, let id = app.bundleID, running.contains(id) {
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
            marker.backgroundColor = accent.cgColor
            marker.shadowColor = accent.cgColor
            marker.shadowOpacity = 0.9
            marker.shadowRadius = 4
            marker.shadowOffset = .zero
            marker.cornerRadius = 1.5
            marker.opacity = 0
            host.addSublayer(marker)
        }
        hovered = nil
        registerForDraggedTypes([.fileURL])
    }

    // MARK: Editing

    private var pinnedCount: Int { apps.prefix { $0.pinned }.count }

    /// The pinned insertion index (0…pinnedCount) for a point, by the gaps between buttons.
    private func insertionIndex(at p: CGPoint) -> Int {
        let pinned = Array(slots.prefix(pinnedCount))
        return pinned.firstIndex { p.x < $0.midX } ?? pinned.count
    }

    private func showMarker(at index: Int?) {
        Motion.instant {
            guard let index, !slots.isEmpty else { marker.opacity = 0; return }
            let s = ShellDockView.size, cy = slots[0].midY
            let x: CGFloat
            if index < pinnedCount { x = slots[index].minX - ShellDockView.gap / 2 }
            else if pinnedCount > 0 { x = slots[pinnedCount - 1].maxX + ShellDockView.gap / 2 }
            else { x = ShellDockView.pad / 2 }
            marker.frame = CGRect(x: x - 1.5, y: cy - s / 2, width: 3, height: s)
            marker.opacity = 1
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press, apps[press.index].pinned else { return }
        let p = convert(event.locationInWindow, from: nil)
        if !dragging {
            guard hypot(p.x - press.start.x, p.y - press.start.y) > 5 else { return }
            dragging = true
            setHover(nil)
        }
        let b = buttons[press.index], r = slots[press.index]
        // Off the dock (well above the rail) means "remove".
        let removing = p.y < ShellDockView.labelRoom - 12
        Motion.instant {
            b.position = CGPoint(x: p.x, y: removing ? p.y : r.midY)
            b.opacity = removing ? 0.45 : 1
            rings[press.index].opacity = 0
        }
        showMarker(at: removing ? nil : insertionIndex(at: p))
        showLabel(removing ? "REMOVE" : apps[press.index].name.uppercased(), over: CGRect(x: p.x - 1, y: 0, width: 2, height: 1))
    }

    override func mouseUp(with event: NSEvent) {
        defer { press = nil; dragging = false }
        guard let press else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard dragging else {
            // A plain click: open the app, or show the folder.
            guard index(event) == press.index else { return }
            let app = apps[press.index]
            if app.folder, let window {
                onFolder?(app, window.convertToScreen(convert(slots[press.index], to: nil)))
            } else {
                onClick?(app)
            }
            return
        }
        showMarker(at: nil)
        let app = apps[press.index]
        if p.y < ShellDockView.labelRoom - 12 {
            SoundPlayer.shared.play(.back)
            onRemove?(app)
        } else {
            var to = insertionIndex(at: p)
            if to > press.index { to -= 1 }
            if to != press.index { onMove?(press.index, to) }
        }
        // Snap back; a move or removal rebuilds the dock from the store.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        buttons[press.index].position = CGPoint(x: slots[press.index].midX, y: slots[press.index].midY)
        buttons[press.index].opacity = 1
        CATransaction.commit()
    }

    private func showLabel(_ text: String, over r: CGRect) {
        Motion.instant {
            label.string = text
            let tw = min(label.preferredFrameSize().width + 18, 240)
            let x = min(max(r.midX - tw / 2, 2), bounds.width - tw - 2)
            labelBack.frame = CGRect(x: x, y: 4, width: tw, height: 22)
            label.frame = CGRect(x: x, y: 8, width: tw, height: 16)
            label.opacity = 1
            labelBack.opacity = 1
        }
    }

    // Drops from Finder (when the dock is up while Finder is in front: always-on mode).
    private func droppedURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !droppedURLs(sender).isEmpty else { return [] }
        showMarker(at: insertionIndex(at: convert(sender.draggingLocation, from: nil)))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { showMarker(at: nil) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedURLs(sender)
        showMarker(at: nil)
        guard !urls.isEmpty else { return false }
        onDrop?(urls, insertionIndex(at: convert(sender.draggingLocation, from: nil)))
        SoundPlayer.shared.play(.select)
        return true
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
        press = (i, convert(event.locationInWindow, from: nil))
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.88
        pulse.toValue = 1
        pulse.duration = 0.18
        buttons[i].add(pulse, forKey: "pulse")
        SoundPlayer.shared.play(.select)
    }
}
