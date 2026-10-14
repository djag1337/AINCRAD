import AppKit

private struct ShellApp: Equatable {
    var name: String
    var url: URL
    var bundleID: String?
    var pinned: Bool
}

/// A borderless panel above the launcher that never takes key status, so clicking the shell
/// doesn't close the launcher underneath it.
final class ShellPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Layer-hosting, top-left-origin view; subclasses lay out CALayers directly.
private class ShellLayerView: NSView {
    let host = CALayer()
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        host.isGeometryFlipped = true
        layer = host
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func text(_ s: String, _ font: NSFont, _ color: NSColor, align: CATextLayerAlignmentMode = .left) -> CATextLayer {
        let t = CATextLayer()
        t.string = s
        t.font = font
        t.fontSize = font.pointSize
        t.foregroundColor = color.cgColor
        t.alignmentMode = align
        t.truncationMode = .end
        t.contentsScale = window?.backingScaleFactor ?? 2
        return t
    }
}

// MARK: Top bar

/// Full-width SAO bar over the menu bar: player block and active app on the left, status and
/// clock on the right. The centre stays empty for notch islands (Alcove, boringNotch, real notches).
private final class ShellBarView: ShellLayerView {
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

// MARK: Dock

/// SAO dock: the launcher's own glass buttons on a slim rail, with hover lift, accent ring,
/// the app's name above it, running dots, and a divider before running-only apps.
private final class ShellDockView: ShellLayerView {
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

// MARK: Controller

/// Optional desktop shell: a full-width SAO top bar on every display and an SAO dock of pinned
/// and running apps, shown with the launcher or (alwaysOn) the whole time AINCRAD runs. Each
/// lives in its own non-key panel, so clicking them never steals focus or closes the launcher.
///
/// In always-on mode the bars sit over Apple's menu bar everywhere. Over a full-screen app they
/// keep out of the way and only slide in when the pointer reaches the screen edge, covering the
/// menu bar and Dock macOS would otherwise reveal there.
final class ShellController: NSObject {
    private struct Bar {
        let panel: ShellPanel
        let view: ShellBarView
        let display: CGDirectDisplayID
    }

    /// How a panel behaves while the launcher is closed.
    private enum EdgeMode {
        case solid   // always shown
        case peek    // hidden; shown while the pointer is at its screen edge
        case yield   // shown; hidden while the pointer is at its edge (lets the real menu bar through)
        case off     // hidden
    }

    private var bars: [Bar] = []
    private var dockPanel: ShellPanel?
    private var dockView: ShellDockView?
    private var modes: [ObjectIdentifier: EdgeMode] = [:]
    private var pointerActive = Set<ObjectIdentifier>()
    private var revertWork: [ObjectIdentifier: DispatchWorkItem] = [:]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var pointerMonitors: [Any] = []
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    private var theme = Theme.classic
    private(set) var visible = false
    var openLauncher: (() -> Void)?
    var playerName = ""
    /// The app the launcher was opened over: the dock offers its menus, the bar shows its name.
    var targetApp: NSRunningApplication?
    var closeLauncher: (() -> Void)?
    private let menus = AppMenuPanel()
    /// Keep the shell up while the launcher is closed too (it then replaces Apple's menu bar and Dock).
    var alwaysOn = false
    /// Let the real menu bar through when the pointer reaches the top edge.
    var revealMenus = false
    private var launcherOpen = false

    /// Screenshot mode (launch with AINCRAD_DEMO=1): a stock dock and no open-app name.
    static let demo = ProcessInfo.processInfo.environment["AINCRAD_DEMO"] == "1"
    private static let demoApps = ["/System/Library/CoreServices/Finder.app", "/Applications/Safari.app", "/System/Applications/Mail.app",
                                   "/System/Applications/Messages.app", "/System/Applications/Music.app", "/System/Applications/Photos.app",
                                   "/System/Applications/Calendar.app", "/System/Applications/App Store.app", "/System/Applications/System Settings.app"]

    static let dockHeight = ShellDockView.size + 24 + ShellDockView.labelRoom
    /// Height of the top bar on `screen`: the menu bar it covers, so windows below are never hidden.
    static func barHeight(for screen: NSScreen) -> CGFloat {
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return menuBar > 0 ? menuBar : NSStatusBar.system.thickness
    }

    func setLauncherOpen(_ open: Bool, enabled: Bool, hideMenuBar: Bool, hideDock: Bool, theme: Theme) {
        self.theme = theme
        launcherOpen = open
        if open && enabled && !alwaysOn && (hideMenuBar || hideDock) {
            if previousPresentationOptions == nil { previousPresentationOptions = NSApp.presentationOptions }
            var options = previousPresentationOptions ?? []
            if hideMenuBar { options.insert(.autoHideMenuBar) }
            if hideDock || hideMenuBar { options.insert(.autoHideDock) }
            NSApp.presentationOptions = options
        } else if let previousPresentationOptions {
            NSApp.presentationOptions = previousPresentationOptions
            self.previousPresentationOptions = nil
        }
        enabled && (open || alwaysOn) ? show() : hide()
    }

    func show() {
        let launcherScreen = NSApp.windows.first(where: { $0 is LauncherPanel && $0.isVisible })?.screen
        let wasVisible = visible
        visible = true
        // With the launcher only, the shell appears on the launcher's display; always-on covers every display.
        let screens = alwaysOn ? NSScreen.screens : [launcherScreen ?? NSScreen.main].compactMap { $0 }
        let level = NSWindow.Level(rawValue: launcherOpen ? NSWindow.Level.popUpMenu.rawValue + 1 : NSWindow.Level.popUpMenu.rawValue - 1)
        // Joining full-screen Spaces lets the bars cover the menu bar macOS reveals there.
        let behavior: NSWindow.CollectionBehavior = alwaysOn
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            : [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        var kept: [Bar] = []
        for screen in screens {
            let id = screen.displayID
            let bar = bars.first { $0.display == id } ?? Bar(panel: ShellPanel(), view: ShellBarView(frame: .zero), display: id)
            bar.panel.contentView = bar.view
            let sf = screen.frame, h = ShellController.barHeight(for: screen)
            bar.panel.setFrame(NSRect(x: sf.minX, y: sf.maxY - h, width: sf.width, height: h), display: false)
            bar.view.onClick = { [weak self] in self?.openLauncher?() }
            bar.view.onMenus = { [weak self, weak panel = bar.panel] rect in
                guard let self, let panel else { return }
                self.showMenus(from: rect, panel: panel)
            }
            bar.view.onExtras = { [weak self, weak panel = bar.panel] rect in
                guard let self, let panel else { return }
                self.showExtras(from: rect, panel: panel)
            }
            bar.view.build(theme: theme)
            kept.append(bar)
        }
        for old in bars where !kept.contains(where: { $0.display == old.display }) { old.panel.orderOut(nil) }
        bars = kept

        let dock = dockPanel ?? ShellPanel()
        let dv = dockView ?? ShellDockView(frame: .zero)
        dock.contentView = dv
        dv.onClick = { [weak self] app in self?.activate(app) }
        dv.onContext = { [weak self] app, rect in self?.showContext(for: app, from: rect) }
        dockPanel = dock
        dockView = dv

        let panels = bars.map(\.panel) + [dock]
        for panel in panels {
            panel.level = level
            panel.collectionBehavior = behavior
        }
        refresh()
        if launcherOpen { prefetchExtras() }
        updateModes(animated: wasVisible)
        if !wasVisible {
            for panel in panels where currentlyShown(panel) {
                panel.alphaValue = 0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    panel.animator().alphaValue = 1
                }
            }
        }
        panels.forEach { $0.orderFrontRegardless() }
        alwaysOn && !launcherOpen ? startPointerMonitor() : stopPointerMonitor()
        if timer == nil {
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                self?.refreshBars()
                self?.updateModes(animated: true)
            }
            t.tolerance = 0.5
            RunLoop.main.add(t, forMode: .common)
            timer = t
            let center = NSWorkspace.shared.notificationCenter
            observers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                         NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification].map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.refresh()
                    // A full-screen app's window lands a moment after its Space appears.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.updateModes(animated: true) }
                }
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
                guard let self, self.visible else { return }
                self.show()
            })
        }
    }

    func hide() {
        menus.hide()
        stopPointerMonitor()
        visible = false
        timer?.invalidate()
        timer = nil
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
        observers = []
        for panel in bars.map(\.panel) + [dockPanel].compactMap({ $0 }) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.14
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                if self?.visible != true { panel.orderOut(nil) }
            })
        }
    }

    // MARK: Edges and full screen

    private func updateModes(animated: Bool) {
        guard visible else { return }
        let fullScreen = fullScreenDisplays()
        for bar in bars {
            let fs = fullScreen.contains(bar.display)
            let mode: EdgeMode = launcherOpen || !alwaysOn ? .solid
                : fs ? (revealMenus ? .off : .peek)
                : (revealMenus ? .yield : .solid)
            setMode(mode, for: bar.panel, animated: animated)
        }
        if let dock = dockPanel {
            let main = NSScreen.screens.first?.displayID
            let dockScreen = dock.screen?.displayID ?? main
            let mode: EdgeMode = launcherOpen || !alwaysOn ? .solid : fullScreen.contains(dockScreen ?? 0) ? .peek : .solid
            setMode(mode, for: dock, animated: animated)
        }
    }

    private func setMode(_ mode: EdgeMode, for panel: ShellPanel, animated: Bool) {
        let key = ObjectIdentifier(panel)
        guard modes[key] != mode || !animated else { return }
        modes[key] = mode
        pointerActive.remove(key)
        revertWork.removeValue(forKey: key)?.cancel()
        apply(panel, animated: animated)
    }

    private func currentlyShown(_ panel: ShellPanel) -> Bool {
        let key = ObjectIdentifier(panel)
        switch modes[key] ?? .solid {
        case .solid: return true
        case .off: return false
        case .peek: return pointerActive.contains(key)
        case .yield: return !pointerActive.contains(key)
        }
    }

    private func apply(_ panel: ShellPanel, animated: Bool) {
        let shown = currentlyShown(panel)
        panel.ignoresMouseEvents = !shown
        guard animated else { panel.alphaValue = shown ? 1 : 0; return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = shown ? 1 : 0
        }
    }

    /// Displays whose frontmost content is a full-screen window (a full-screen Space, or a
    /// borderless full-screen game), so the shell steps out of its way.
    private func fullScreenDisplays() -> Set<CGDirectDisplayID> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let top = NSScreen.screens.first?.frame.maxY else { return [] }
        var out = Set<CGDirectDisplayID>()
        for w in list where (w[kCGWindowLayer as String] as? Int) == 0 && (w[kCGWindowOwnerPID as String] as? pid_t) != getpid() {
            guard let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict) else { continue }
            for screen in NSScreen.screens {
                let f = screen.frame
                if r.equalTo(CGRect(x: f.minX, y: top - f.maxY, width: f.width, height: f.height)) { out.insert(screen.displayID) }
            }
        }
        return out
    }

    // MARK: Pointer

    /// Mouse-moved monitors need no permission. Each check is a few comparisons.
    private func startPointerMonitor() {
        guard pointerMonitors.isEmpty else { return }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in self?.pointerMoved() }) {
            pointerMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] e in self?.pointerMoved(); return e }) {
            pointerMonitors.append(l)
        }
    }

    private func stopPointerMonitor() {
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors = []
        revertWork.values.forEach { $0.cancel() }
        revertWork = [:]
        pointerActive = []
    }

    private func pointerMoved() {
        guard alwaysOn, !launcherOpen else { return }
        let p = NSEvent.mouseLocation
        for bar in bars {
            guard let screen = bar.panel.screen else { continue }
            let f = bar.panel.frame
            let inX = p.x >= f.minX && p.x < f.maxX
            track(bar.panel, triggered: inX && p.y >= screen.frame.maxY - 2, inside: inX && p.y >= f.minY - 1)
        }
        if let dock = dockPanel, let screen = dock.screen {
            let sf = screen.frame, f = dock.frame
            let onScreen = p.x >= sf.minX && p.x < sf.maxX
            track(dock, triggered: onScreen && p.y <= sf.minY + 2, inside: f.insetBy(dx: -10, dy: -10).contains(p))
        }
    }

    /// `triggered`: the pointer is at the edge; `inside`: it's over the panel (keeps a peeked panel open).
    private func track(_ panel: ShellPanel, triggered: Bool, inside: Bool) {
        let key = ObjectIdentifier(panel)
        guard let mode = modes[key], mode == .peek || mode == .yield else { return }
        let wasActive = pointerActive.contains(key)
        let active = mode == .peek ? (triggered || (wasActive && inside)) : inside
        if active {
            revertWork.removeValue(forKey: key)?.cancel()
            if !wasActive {
                pointerActive.insert(key)
                apply(panel, animated: true)
            }
        } else if wasActive && revertWork[key] == nil {
            // A short grace period, so brushing past or moving into an open menu doesn't flicker.
            let work = DispatchWorkItem { [weak self] in
                self?.revertWork[key] = nil
                self?.pointerActive.remove(key)
                self?.apply(panel, animated: true)
            }
            revertWork[key] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (mode == .peek ? 0.4 : 0.8), execute: work)
        }
    }

    // MARK: Content

    private func refresh() {
        guard visible, let dv = dockView, let dock = dockPanel else { return }
        // The dock lives on the main display when always on, otherwise with the launcher.
        guard let screen = (alwaysOn && !launcherOpen ? NSScreen.screens.first : bars.first?.panel.screen) ?? NSScreen.main else { return }
        let apps = shellApps()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let width = min(ShellDockView.width(for: apps), screen.frame.width - 80)
        let sf = screen.frame
        // Sit above the macOS Dock when it's showing.
        dock.setFrame(NSRect(x: sf.midX - width / 2, y: screen.visibleFrame.minY + 6, width: width, height: ShellController.dockHeight), display: false)
        dv.frame = NSRect(origin: .zero, size: dock.frame.size)
        dv.set(apps: apps, running: running, frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, theme: theme)
        refreshBars()
    }

    private func refreshBars() {
        guard visible, !bars.isEmpty else { return }
        let hub = DataHub.shared
        let name = playerName.isEmpty ? (NSFullUserName().split(separator: " ").first.map(String.init) ?? "Player") : playerName
        let lv = Int(ProcessInfo.processInfo.systemUptime / 3600) + 1
        let battery = hub.sample(.battery)
        let memory = hub.sample(.memory)
        let hp = battery?.fraction ?? (1 - (memory?.fraction ?? 0))
        let cpu = hub.sample(.cpu)?.fraction.map { "CPU \(Int($0 * 100))%" } ?? "CPU —"
        let mem = memory?.fraction.map { "MEM \(Int($0 * 100))%" } ?? ""
        let power = battery?.fraction.map { "BAT \(Int($0 * 100))%" }
        let status = [cpu, mem, power].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "   ·   ")
        // While the launcher is up, AINCRAD itself is frontmost; show the app underneath instead.
        let front = (launcherOpen ? targetApp : nil)
            ?? NSWorkspace.shared.runningApplications.first { $0.isActive && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            ?? NSWorkspace.shared.menuBarOwningApplication
        let appName = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? "Desktop" : (front?.localizedName ?? "Desktop")
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM  ·  h:mm a"
        let clock = df.string(from: Date())
        for bar in bars {
            bar.view.update(player: name, hp: hp, lv: lv, app: ShellController.demo ? "" : appName,
                            icon: ShellController.demo ? nil : front?.icon, status: status, clock: clock)
        }
    }

    /// The app whose menus the bar offers: the one the launcher opened over, else the frontmost.
    private var menuApp: NSRunningApplication? {
        if launcherOpen, let t = targetApp, !t.isTerminated { return t }
        let front = NSWorkspace.shared.frontmostApplication
        return front?.processIdentifier == getpid() ? targetApp : front
    }

    private func showMenus(from rect: NSRect, panel: ShellPanel) {
        guard let app = menuApp, let screen = panel.screen else { return }
        if menus.isOpen { menus.hide(); return }
        guard AXIsProcessTrusted() else {
            Log.info("app menus: needs Accessibility")
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
            return
        }
        menus.show(app: app, anchor: rect, screen: screen, theme: theme, level: panel.level) { [weak self] node in
            // Hand the app back its focus first: menu commands act on its key window.
            if self?.launcherOpen == true { self?.closeLauncher?() }
            app.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Log.info("app menus: \(app.localizedName ?? "?") › \(node.title)")
                AXMenus.press(node)
            }
        }
    }

    /// Runs a chosen custom item after the launcher (if open) has closed, so it doesn't steal focus back.
    private func perform(_ node: AXMenus.Node) {
        if launcherOpen { closeLauncher?() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { AXMenus.press(node) }
    }

    /// Right-click on a dock app: its windows, then Open/Show, Show in Finder, Hide and Quit.
    private func showContext(for app: ShellApp, from rect: NSRect) {
        guard let dock = dockPanel, let screen = dock.screen else { return }
        if menus.isOpen { menus.hide(); return }
        let running = app.bundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        var nodes: [AXMenus.Node] = []
        if let running {
            let windows = ShellController.windows(of: running)
            nodes += windows.map { w in
                .action(w.title + (w.minimized ? "  (minimized)" : "")) {
                    if w.minimized { AXUIElementSetAttributeValue(w.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
                    AXUIElementPerformAction(w.element, kAXRaiseAction as CFString)
                    running.activate(options: [])
                }
            }
            if !windows.isEmpty { nodes.append(.separatorLine) }
            nodes.append(.action("Show") { AppOpener.open(app.url, bundleID: app.bundleID) })
        } else {
            nodes.append(.action("Open") { AppOpener.open(app.url, bundleID: app.bundleID) })
        }
        nodes.append(.action("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) })
        if let running {
            nodes.append(.separatorLine)
            nodes.append(.action(running.isHidden ? "Unhide" : "Hide") { running.isHidden ? running.unhide() : running.hide() })
            nodes.append(.action("Quit") { running.terminate() })
        }
        menus.show(nodes, title: app.name, anchor: rect, screen: screen, theme: theme, level: dock.level, rising: true) { [weak self] node in
            self?.perform(node)
        }
    }

    /// The menu bar icons, read in the background when the launcher opens (asking every running
    /// app takes a second or two), so a right-click on the bar can show them at once.
    private var extrasCache: (time: Date, nodes: [AXMenus.Node])?
    private var extrasLoading = false

    private func prefetchExtras(then done: (([AXMenus.Node]) -> Void)? = nil) {
        guard AXIsProcessTrusted(), !extrasLoading else { return }
        extrasLoading = true
        let start = CACurrentMediaTime()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let extras = AXMenus.extras()
            DispatchQueue.main.async {
                guard let self else { return }
                self.extrasLoading = false
                self.extrasCache = (Date(), extras)
                Log.info(String(format: "shell: %d menu bar icons read in %.0f ms", extras.count, (CACurrentMediaTime() - start) * 1000))
                done?(extras)
            }
        }
    }

    /// Right-click on the top bar: the menu bar icons (Wi-Fi, Sound, status items).
    private func showExtras(from rect: NSRect, panel: ShellPanel) {
        guard let screen = panel.screen else { return }
        if menus.isOpen { menus.hide(); return }
        guard AXIsProcessTrusted() else { return }
        let present: ([AXMenus.Node]) -> Void = { [weak self] extras in
            guard let self, self.visible else { return }
            let nodes = extras.isEmpty ? [AXMenus.Node(title: "No menu bar icons found", enabled: false)] : extras
            self.menus.show(nodes, title: "Menu bar", anchor: rect, screen: screen, theme: self.theme, level: panel.level,
                            rising: false) { [weak self] node in self?.perform(node) }
        }
        if let cache = extrasCache, Date().timeIntervalSince(cache.time) < 120 {
            present(cache.nodes)
            prefetchExtras()   // refresh quietly for next time
        } else {
            prefetchExtras(then: present)
        }
    }

    private struct AXWindow { let element: AXUIElement; let title: String; let minimized: Bool }

    private static func windows(of app: NSRunningApplication) -> [AXWindow] {
        guard AXIsProcessTrusted() else { return [] }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list.compactMap { w in
            var t: CFTypeRef?, m: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
            AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &m)
            guard let title = t as? String, !title.isEmpty else { return nil }
            return AXWindow(element: w, title: title, minimized: (m as? Bool) ?? false)
        }
    }

    private func activate(_ app: ShellApp) {
        Log.info("shell dock: \(app.name)")
        // Close the launcher first so its losing focus doesn't race the app coming forward.
        if launcherOpen { closeLauncher?() }
        AppOpener.open(app.url, bundleID: app.bundleID)
    }

    private func shellApps() -> [ShellApp] {
        if ShellController.demo {
            return ShellController.demoApps.map(URL.init(fileURLWithPath:)).filter { FileManager.default.fileExists(atPath: $0.path) }.map {
                ShellApp(name: $0.deletingPathExtension().lastPathComponent, url: $0, bundleID: Bundle(url: $0)?.bundleIdentifier, pinned: true)
            }
        }
        var out = dockApps(), seen = Set(out.compactMap(\.bundleID))
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.bundleIdentifier != Bundle.main.bundleIdentifier {
            guard let url = app.bundleURL, let id = app.bundleIdentifier, seen.insert(id).inserted else { continue }
            out.append(ShellApp(name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, url: url, bundleID: id, pinned: false))
        }
        return out
    }

    private func dockApps() -> [ShellApp] {
        guard let raw = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else { return [] }
        return raw.compactMap { item in
            guard let tile = item["tile-data"] as? [String: Any], let files = tile["file-data"] as? [String: Any],
                  let value = files["_CFURLString"] as? String,
                  let url = URL(string: value), url.isFileURL else { return nil }
            let id = tile["bundle-identifier"] as? String ?? Bundle(url: url)?.bundleIdentifier
            let name = tile["file-label"] as? String ?? url.deletingPathExtension().lastPathComponent
            return ShellApp(name: name, url: url, bundleID: id, pinned: true)
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
