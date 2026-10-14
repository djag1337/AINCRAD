import AppKit

/// Runs a session event tap on its own thread and feeds mouse buttons to `GestureRecognizer`.
/// The tap thread never waits on the main thread, so a busy UI can't stall the system's mouse.
/// Needs Accessibility permission (an active tap that can hold back a right click).
final class GestureMonitor {
    private static let replayMarker: Int64 = 0x4149_4E43 // 'AINC'

    /// Called on the main thread with the gesture's start point in CG global coordinates.
    var onTrigger: ((CGPoint) -> Void)?

    private let lock = NSLock()
    private var settings: GestureSettings
    private var launcherOpen = false
    private var frontmostBundleID: String?
    private var frontmostPID: pid_t = 0
    private var screenRects: [CGRect] = []

    // Tap-thread state.
    private var recognizer: GestureRecognizer
    private var heldRightDown: CGEvent?
    private var timer: CFRunLoopTimer?
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var observers: [NSObjectProtocol] = []

    private(set) var isRunning = false

    init(settings: GestureSettings) {
        self.settings = settings
        recognizer = GestureRecognizer(config: GestureMonitor.config(settings))
    }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func update(_ settings: GestureSettings) {
        lock.lock()
        self.settings = settings
        lock.unlock()
        let config = GestureMonitor.config(settings)
        perform { $0.recognizer.config = config }
    }

    func setLauncherOpen(_ open: Bool) {
        lock.lock()
        launcherOpen = open
        lock.unlock()
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard GestureMonitor.hasPermission else { return false }
        refreshEnvironment()
        let ws = NSWorkspace.shared.notificationCenter
        observers = [
            ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshEnvironment()
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshEnvironment()
            },
        ]
        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [weak self] in
            self?.runTap(ready: ready)
        }
        t.name = "AINCRAD gesture tap"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
        ready.wait()
        isRunning = tap != nil
        if isRunning { Log.info("gesture tap started") } else { Log.error("gesture tap could not be created") }
        return isRunning
    }

    func stop() {
        guard isRunning else { return }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        observers = []
        if let rl = runLoop {
            CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) { [weak self] in
                guard let self else { return }
                if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
                self.flushHeld()
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(rl)
        }
        isRunning = false
        Log.info("gesture tap stopped")
    }

    // MARK: Tap thread

    private func runTap(ready: DispatchSemaphore) {
        let mask: CGEventMask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                 .rightMouseDown, .rightMouseUp, .rightMouseDragged]
            .reduce(0) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            Unmanaged<GestureMonitor>.fromOpaque(refcon!).takeUnretainedValue().handle(type: type, event: event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { ready.signal(); return }
        runLoop = CFRunLoopGetCurrent()
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        ready.signal()
        CFRunLoopRun()
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        self.tap = nil
        runLoop = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            flushHeld()
            recognizer.reset()
            Log.error("gesture tap was disabled by the system (\(type.rawValue)); re-enabled")
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == GestureMonitor.replayMarker {
            return Unmanaged.passUnretained(event)
        }
        guard let kind = GestureMonitor.kind(type) else { return Unmanaged.passUnretained(event) }

        if recognizer.isIdle {
            lock.lock()
            let open = launcherOpen
            lock.unlock()
            if open || (kind == .rightDown && shouldIgnoreHere()) { return Unmanaged.passUnretained(event) }
        }

        let decision = recognizer.handle(GestureRecognizer.Event(kind: kind, location: event.location,
                                                                  time: ProcessInfo.processInfo.systemUptime))
        if kind == .rightDown, recognizer.isPending {
            heldRightDown = event.copy()
            scheduleTimeout()
        } else if !recognizer.isPending {
            cancelTimeout()
        }
        for r in decision.replay {
            post(r == .heldRightDown ? heldRightDown : event.copy())
            if r == .heldRightDown { heldRightDown = nil }
        }
        if !recognizer.isPending && !decision.replay.contains(.heldRightDown) { heldRightDown = nil }
        if let point = decision.trigger {
            lock.lock()
            let delay = settings.activationDelayMs / 1000
            lock.unlock()
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.onTrigger?(point) }
        }
        return decision.deliver ? Unmanaged.passUnretained(event) : nil
    }

    /// Checks every 30 ms while a right press is held back (only then), so both the chord
    /// window and right-button mode's hold/slide limits are honoured.
    private func scheduleTimeout() {
        cancelTimeout()
        let t = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 0.03, 0.03, 0, 0) { [weak self] _ in
            guard let self else { return }
            if self.recognizer.timeout(now: ProcessInfo.processInfo.systemUptime).contains(.heldRightDown) {
                self.post(self.heldRightDown)
                self.heldRightDown = nil
            }
            if !self.recognizer.isPending { self.cancelTimeout() }
        }
        timer = t
        CFRunLoopAddTimer(runLoop, t, .commonModes)
    }

    private func cancelTimeout() {
        if let timer { CFRunLoopTimerInvalidate(timer) }
        timer = nil
    }

    /// Never leave a right press swallowed: deliver it if we're shutting down mid-chord-window.
    private func flushHeld() {
        cancelTimeout()
        if recognizer.isPending { post(heldRightDown) }
        heldRightDown = nil
    }

    private func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: GestureMonitor.replayMarker)
        event.post(tap: .cgSessionEventTap)
    }

    private func perform(_ block: @escaping (GestureMonitor) -> Void) {
        guard let rl = runLoop else { block(self); return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            if let self { block(self) }
        }
        CFRunLoopWakeUp(rl)
    }

    // MARK: Exclusions

    private func refreshEnvironment() {
        let app = NSWorkspace.shared.frontmostApplication
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let rects = NSScreen.screens.map { s in
            CGRect(x: s.frame.minX, y: primaryHeight - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }
        lock.lock()
        frontmostBundleID = app?.bundleIdentifier
        frontmostPID = app?.processIdentifier ?? 0
        screenRects = rects
        lock.unlock()
    }

    /// Excluded apps, and (optionally) any app whose frontmost window covers a whole screen,
    /// which catches full-screen apps and borderless full-screen games.
    private func shouldIgnoreHere() -> Bool {
        lock.lock()
        let s = settings, bundle = frontmostBundleID, pid = frontmostPID, rects = screenRects
        lock.unlock()
        if let bundle, s.excludedApps.contains(bundle) { return true }
        guard s.disableInFullScreen, pid != 0,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
            if let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b),
               rects.contains(where: { $0.equalTo(r) }) {
                return true
            }
        }
        return false
    }

    private static func kind(_ type: CGEventType) -> GestureRecognizer.Kind? {
        switch type {
        case .leftMouseDown: return .leftDown
        case .leftMouseUp: return .leftUp
        case .leftMouseDragged: return .leftDrag
        case .rightMouseDown: return .rightDown
        case .rightMouseUp: return .rightUp
        case .rightMouseDragged: return .rightDrag
        default: return nil
        }
    }

    private static func config(_ s: GestureSettings) -> GestureRecognizer.Config {
        GestureRecognizer.Config(buttons: s.buttons, slide: s.slide == "none" && s.buttons == "right" ? "down" : s.slide,
                                 distance: CGFloat(s.distance),
                                 chordWindow: s.chordWindowMs / 1000, maxSlide: s.maxSlideMs / 1000)
    }
}
