import AppKit
import ApplicationServices

/// Watches Notification Center's banners through the Accessibility API and reports each new
/// one (app, title, body), optionally closing the original. There is no public API for other
/// apps' notifications; this needs Accessibility permission and relies on Notification
/// Center's UI structure, so it's written to degrade quietly if that changes.
final class NotificationMirror {
    struct Note: Equatable {
        var app: String
        var title: String
        var body: String
    }

    var onNote: ((Note) -> Void)?
    var hideOriginals = true
    private(set) var isRunning = false

    private var observer: AXObserver?
    private var pid: pid_t = 0
    private var launchObserver: NSObjectProtocol?
    private var recent: [(note: Note, time: Date)] = []
    private var loggedLayouts = 0

    static let bundleID = "com.apple.notificationcenterui"

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard AXIsProcessTrusted() else { return false }
        isRunning = true
        attach()
        // Notification Center can restart; follow it.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == NotificationMirror.bundleID else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.attach() }
        }
        return true
    }

    func stop() {
        detach()
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        launchObserver = nil
        isRunning = false
    }

    private func attach() {
        detach()
        guard let nc = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == NotificationMirror.bundleID }) else {
            Log.error("notifications: Notification Center isn't running")
            return
        }
        pid = nc.processIdentifier
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let mirror = Unmanaged<NotificationMirror>.fromOpaque(refcon).takeUnretainedValue()
            // Banner content fills in just after the window appears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { mirror.scan(element) }
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else {
            Log.error("notifications: couldn't observe Notification Center")
            return
        }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXWindowCreatedNotification, kAXCreatedNotification] {
            AXObserverAddNotification(obs, app, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        Log.info("notifications: watching Notification Center (pid \(pid))")
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
    }

    // MARK: Reading banners

    private func scan(_ root: AXUIElement) {
        var banners: [AXUIElement] = []
        collect(root, depth: 0, into: &banners)
        for banner in banners {
            guard let note = read(banner) else { continue }
            recent.removeAll { Date().timeIntervalSince($0.time) > 4 }
            guard !recent.contains(where: { $0.note == note }) else { continue }
            recent.append((note, Date()))
            onNote?(note)
            if hideOriginals { close(banner) }
        }
    }

    /// Banners are groups whose subrole starts with AXNotificationCenter (Banner / Alert).
    private func collect(_ e: AXUIElement, depth: Int, into out: inout [AXUIElement]) {
        guard depth < 10 else { return }
        if let sub = attr(e, kAXSubroleAttribute) as? String, sub.hasPrefix("AXNotificationCenter") {
            out.append(e)
            return
        }
        for child in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { collect(child, depth: depth + 1, into: &out) }
    }

    private func read(_ banner: AXUIElement) -> Note? {
        var texts: [String] = []
        func gather(_ e: AXUIElement, _ depth: Int) {
            guard depth < 8 else { return }
            if (attr(e, kAXRoleAttribute) as? String) == kAXStaticTextRole as String,
               let v = attr(e, kAXValueAttribute) as? String, !v.isEmpty { texts.append(v) }
            for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { gather(c, depth + 1) }
        }
        gather(banner, 0)
        let desc = (attr(banner, kAXDescriptionAttribute) as? String) ?? ""
        let parts = desc.components(separatedBy: ", ").filter { !$0.isEmpty }
        if loggedLayouts < 3 {
            loggedLayouts += 1
            // Shape only, never the message text.
            Log.info("notifications: banner \(attr(banner, kAXSubroleAttribute) as? String ?? "?") with \(texts.count) texts, \(parts.count) description parts")
        }
        if !texts.isEmpty {
            let app = parts.count > texts.count ? parts[0] : ""
            return Note(app: app, title: texts[0], body: texts.dropFirst().joined(separator: "\n"))
        }
        guard parts.count >= 2 else { return nil }
        return Note(app: parts[0], title: parts[1], body: parts.dropFirst(2).joined(separator: ", "))
    }

    private func close(_ banner: AXUIElement) {
        var names: CFArray?
        AXUIElementCopyActionNames(banner, &names)
        guard let action = (names as? [String])?.first(where: { $0.localizedCaseInsensitiveContains("close") }) else { return }
        AXUIElementPerformAction(banner, action as CFString)
    }

    private func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
}
