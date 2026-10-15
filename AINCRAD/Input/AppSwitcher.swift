import AppKit
import Carbon.HIToolbox

/// Optional ⌘-Tab replacement: an SAO row of your apps, most recently used first. Hold ⌘ and press
/// Tab (⇧Tab goes back, ← → move, Q quits the chosen app, H hides it, Esc cancels); letting go of ⌘
/// switches. A keyboard event tap on its own thread decides what to swallow without waiting on the
/// main thread, so a busy AINCRAD can never stall typing.
final class AppSwitcher {
    static let shared = AppSwitcher()

    private var tap: CFMachPort?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    /// Touched only on the tap thread.
    private var active = false
    private(set) var isRunning = false
    var theme = Theme.classic

    // MRU order of apps, newest first (pids), kept on the main thread.
    private var mru: [pid_t] = []
    private var observer: NSObjectProtocol?

    // Shown while switching (main thread).
    private var apps: [NSRunningApplication] = []
    private var selected = 0
    private let panel = SwitcherPanel()

    // MARK: Start / stop

    func start() {
        guard !isRunning else { return }
        guard AXIsProcessTrusted() else { Log.error("app switcher: needs Accessibility"); return }
        if observer == nil {
            observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
                guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.mru.removeAll { $0 == app.processIdentifier }
                self?.mru.insert(app.processIdentifier, at: 0)
            }
            if let front = NSWorkspace.shared.frontmostApplication { mru = [front.processIdentifier] }
        }
        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [weak self] in
            self?.installTap()
            ready.signal()
            CFRunLoopRun()
        }
        t.name = "AINCRAD app switcher tap"
        t.qualityOfService = .userInteractive
        t.start()
        thread = t
        ready.wait()
        isRunning = tap != nil
        Log.info(isRunning ? "app switcher: on (⌘-Tab)" : "app switcher: tap could not be created")
    }

    func stop() {
        guard isRunning, let loop = runLoop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            if let tap = self?.tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
            self?.tap = nil
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(loop)
        isRunning = false
        DispatchQueue.main.async { self.panel.orderOut(nil) }
        Log.info("app switcher: off")
    }

    private func installTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(mask),
                                callback: { _, type, event, ctx in
                                    let me = Unmanaged<AppSwitcher>.fromOpaque(ctx!).takeUnretainedValue()
                                    return me.handle(type, event)
                                }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: Tap (tap thread)

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        let cmd = flags.contains(.maskCommand)
        if type == .flagsChanged {
            if active && !cmd {
                active = false
                DispatchQueue.main.async { self.commit() }
            }
            return Unmanaged.passUnretained(event)
        }
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let plainCmd = cmd && !flags.contains(.maskControl) && !flags.contains(.maskAlternate)
        if code == kVK_Tab && plainCmd {
            if type == .keyDown {
                let back = flags.contains(.maskShift)
                if !active {
                    active = true
                    DispatchQueue.main.async { self.begin(back: back) }
                } else {
                    DispatchQueue.main.async { self.move(back ? -1 : 1) }
                }
            }
            return nil
        }
        guard active else { return Unmanaged.passUnretained(event) }
        // While switching, these keys belong to the switcher.
        if type == .keyDown {
            switch code {
            case kVK_Escape: active = false; DispatchQueue.main.async { self.cancel() }
            case kVK_LeftArrow: DispatchQueue.main.async { self.move(-1) }
            case kVK_RightArrow: DispatchQueue.main.async { self.move(1) }
            case kVK_ANSI_Q: DispatchQueue.main.async { self.quitSelected() }
            case kVK_ANSI_H: DispatchQueue.main.async { self.hideSelected() }
            default: return Unmanaged.passUnretained(event)
            }
        }
        return [kVK_Escape, kVK_LeftArrow, kVK_RightArrow, kVK_ANSI_Q, kVK_ANSI_H].contains(code) ? nil : Unmanaged.passUnretained(event)
    }

    // MARK: Switching (main thread)

    static func order(_ running: [NSRunningApplication], mru: [pid_t]) -> [NSRunningApplication] {
        running.sorted { a, b in
            let ia = mru.firstIndex(of: a.processIdentifier) ?? Int.max, ib = mru.firstIndex(of: b.processIdentifier) ?? Int.max
            return ia != ib ? ia < ib : (a.localizedName ?? "") < (b.localizedName ?? "")
        }
    }

    private func begin(back: Bool) {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
        apps = AppSwitcher.order(running, mru: mru)
        guard !apps.isEmpty else { return }
        // Like macOS: the first Tab picks the app you used before the current one.
        selected = apps.count > 1 ? (back ? apps.count - 1 : 1) : 0
        panel.show(apps: apps, selected: selected, theme: theme)
        SoundPlayer.shared.play(.open)
    }

    private func move(_ step: Int) {
        guard !apps.isEmpty else { return }
        selected = (selected + step + apps.count) % apps.count
        panel.select(selected)
        SoundPlayer.shared.play(.hover)
    }

    private func commit() {
        panel.orderOut(nil)
        guard apps.indices.contains(selected) else { return }
        let app = apps[selected]
        apps = []
        if let url = app.bundleURL { AppOpener.open(url, bundleID: app.bundleIdentifier) } else { app.activate(options: [.activateAllWindows]) }
    }

    private func cancel() {
        panel.orderOut(nil)
        apps = []
        SoundPlayer.shared.play(.close)
    }

    private func quitSelected() {
        guard apps.indices.contains(selected) else { return }
        apps[selected].terminate()
        apps.remove(at: selected)
        if apps.isEmpty { cancel(); return }
        selected = min(selected, apps.count - 1)
        panel.show(apps: apps, selected: selected, theme: theme)
    }

    private func hideSelected() {
        guard apps.indices.contains(selected) else { return }
        apps[selected].hide()
        move(1)
    }
}

/// The switcher's look: the dock's glass circles on an SAO rail, the chosen one lifted with an
/// accent ring and its name above, centred on the display under the pointer.
private final class SwitcherPanel: NSPanel {
    private let host = CALayer()
    private var circles: [CALayer] = []
    private var rings: [CALayer] = []
    private let label = CATextLayer()
    private let size: CGFloat = 76, gap: CGFloat = 18, pad: CGFloat = 28

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        ignoresMouseEvents = true
        let view = NSView()
        host.isGeometryFlipped = true
        view.layer = host
        view.wantsLayer = true
        contentView = view
    }

    override var canBecomeKey: Bool { false }

    func show(apps: [NSRunningApplication], selected: Int, theme: Theme) {
        let c = theme.colors, accent = themeColor(c.accent), panel = themeColor(c.panel)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let perRow = max(1, Int((screen.visibleFrame.width - 120 - pad * 2 + gap) / (size + gap)))
        let shown = min(apps.count, perRow)
        let w = pad * 2 + CGFloat(shown) * size + CGFloat(max(shown - 1, 0)) * gap, h = size + 92
        setFrame(NSRect(x: screen.frame.midX - w / 2, y: screen.frame.midY - h / 2, width: w, height: h), display: false)
        Motion.instant {
            host.sublayers?.forEach { $0.removeFromSuperlayer() }
            circles = []; rings = []
            let back = CALayer()
            back.frame = CGRect(x: 0, y: 34, width: w, height: h - 34)
            back.backgroundColor = panel.withAlphaComponent(0.95).cgColor
            back.cornerRadius = (h - 34) / 2
            back.borderWidth = theme.effects.borderWidth
            back.borderColor = themeColor(c.panelBorder).cgColor
            back.shadowColor = themeColor(c.shadow).cgColor
            back.shadowOpacity = 0.5
            back.shadowRadius = 14
            back.shadowOffset = CGSize(width: 0, height: 4)
            host.addSublayer(back)
            let line = CALayer()
            line.frame = CGRect(x: 40, y: 34, width: w - 80, height: 2)
            line.backgroundColor = accent.cgColor
            host.addSublayer(line)
            let circle = themeColor(c.circle)
            for (i, app) in apps.prefix(shown).enumerated() {
                let r = CGRect(x: pad + CGFloat(i) * (size + gap), y: 34 + (h - 34 - size) / 2, width: size, height: size)
                let ring = CALayer()
                ring.frame = r.insetBy(dx: -5, dy: -5)
                ring.cornerRadius = (size + 10) / 2
                ring.borderWidth = 2.5
                ring.borderColor = accent.cgColor
                ring.shadowColor = accent.cgColor
                ring.shadowOpacity = 0.9
                ring.shadowRadius = 8
                ring.shadowOffset = .zero
                host.addSublayer(ring)
                let b = CAGradientLayer()
                b.frame = r
                b.cornerRadius = size / 2
                b.colors = [(circle.blended(withFraction: 0.08, of: .white) ?? circle).cgColor, (circle.blended(withFraction: 0.08, of: .black) ?? circle).cgColor]
                b.borderWidth = 1
                b.borderColor = themeColor(c.circleBorder).cgColor
                let icon = CALayer()
                icon.frame = b.bounds.insetBy(dx: 12, dy: 12)
                icon.contents = app.icon?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                icon.contentsGravity = .resizeAspect
                b.addSublayer(icon)
                if app.isHidden { b.opacity = 0.5 }
                host.addSublayer(b)
                circles.append(b)
                rings.append(ring)
            }
            let f = ThemeFonts.display(theme, 14)
            label.font = f
            label.fontSize = f.pointSize
            label.foregroundColor = themeColor(c.panelText).cgColor
            label.backgroundColor = panel.withAlphaComponent(0.95).cgColor
            label.borderColor = accent.cgColor
            label.borderWidth = 1
            label.cornerRadius = 4
            label.alignmentMode = .center
            label.contentsScale = screen.backingScaleFactor
            host.addSublayer(label)
        }
        names = apps.prefix(shown).map { $0.localizedName ?? "App" }
        select(selected)
        orderFrontRegardless()
    }

    private var names: [String] = []

    func select(_ i: Int) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        for (j, b) in circles.enumerated() {
            let on = j == i
            b.transform = on ? CATransform3DMakeTranslation(0, -6, 0) : CATransform3DIdentity
            rings[j].transform = b.transform
            rings[j].opacity = on ? 1 : 0
        }
        if names.indices.contains(i) {
            label.string = names[i].uppercased()
            let tw = min(label.preferredFrameSize().width + 24, frame.width - 8)
            let mid = circles[i].frame.midX
            label.frame = CGRect(x: min(max(mid - tw / 2, 4), frame.width - tw - 4), y: 4, width: tw, height: 24)
        }
        CATransaction.commit()
    }
}
