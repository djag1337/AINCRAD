import AppKit

/// Windows across all apps, through Accessibility: a switcher that lists every window, and
/// layouts (halves, thirds, quarters…) for the window you were using before opening the launcher.
enum WindowControl {
    /// The app the launcher was opened over (set by the app delegate).
    static var targetApp: () -> NSRunningApplication? = { nil }

    // MARK: Layouts

    struct Layout { let id: String; let title: String; let icon: String; let group: String }

    static let layouts: [Layout] = [
        Layout(id: "left", title: "Left Half", icon: "sf:rectangle.lefthalf.inset.filled", group: "Halves"),
        Layout(id: "right", title: "Right Half", icon: "sf:rectangle.righthalf.inset.filled", group: "Halves"),
        Layout(id: "top", title: "Top Half", icon: "sf:rectangle.tophalf.inset.filled", group: "Halves"),
        Layout(id: "bottom", title: "Bottom Half", icon: "sf:rectangle.bottomhalf.inset.filled", group: "Halves"),
        Layout(id: "third-left", title: "Left Third", icon: "sf:rectangle.leadingthird.inset.filled", group: "Thirds"),
        Layout(id: "third-center", title: "Center Third", icon: "sf:rectangle.center.inset.filled", group: "Thirds"),
        Layout(id: "third-right", title: "Right Third", icon: "sf:rectangle.trailingthird.inset.filled", group: "Thirds"),
        Layout(id: "two-thirds-left", title: "Left Two Thirds", icon: "sf:rectangle.leadinghalf.inset.filled", group: "Thirds"),
        Layout(id: "two-thirds-right", title: "Right Two Thirds", icon: "sf:rectangle.trailinghalf.inset.filled", group: "Thirds"),
        Layout(id: "top-left", title: "Top Left", icon: "sf:rectangle.inset.topleft.filled", group: "Quarters"),
        Layout(id: "top-right", title: "Top Right", icon: "sf:rectangle.inset.topright.filled", group: "Quarters"),
        Layout(id: "bottom-left", title: "Bottom Left", icon: "sf:rectangle.inset.bottomleft.filled", group: "Quarters"),
        Layout(id: "bottom-right", title: "Bottom Right", icon: "sf:rectangle.inset.bottomright.filled", group: "Quarters"),
        Layout(id: "max", title: "Maximize", icon: "sf:rectangle.inset.filled", group: "Size"),
        Layout(id: "almost", title: "Almost Maximize", icon: "sf:rectangle.center.inset.filled", group: "Size"),
        Layout(id: "center", title: "Center", icon: "sf:rectangle.center.inset.filled", group: "Size"),
        Layout(id: "next-display", title: "Move to Next Display", icon: "sf:display.2", group: "Size"),
        Layout(id: "restore", title: "Restore Previous Size", icon: "sf:arrow.uturn.backward", group: "Size"),
    ]

    /// Where a window goes on `screen` (Cocoa coordinates: origin bottom-left). `current` is used
    /// by Center, which keeps the window's size. Nil for layouts that aren't a fixed frame.
    static func frame(for layout: String, in screen: CGRect, current: CGRect) -> CGRect? {
        let s = screen, w = s.width, h = s.height
        switch layout {
        case "left": return CGRect(x: s.minX, y: s.minY, width: w / 2, height: h)
        case "right": return CGRect(x: s.midX, y: s.minY, width: w / 2, height: h)
        case "top": return CGRect(x: s.minX, y: s.midY, width: w, height: h / 2)
        case "bottom": return CGRect(x: s.minX, y: s.minY, width: w, height: h / 2)
        case "third-left": return CGRect(x: s.minX, y: s.minY, width: w / 3, height: h)
        case "third-center": return CGRect(x: s.minX + w / 3, y: s.minY, width: w / 3, height: h)
        case "third-right": return CGRect(x: s.minX + 2 * w / 3, y: s.minY, width: w / 3, height: h)
        case "two-thirds-left": return CGRect(x: s.minX, y: s.minY, width: 2 * w / 3, height: h)
        case "two-thirds-right": return CGRect(x: s.minX + w / 3, y: s.minY, width: 2 * w / 3, height: h)
        case "top-left": return CGRect(x: s.minX, y: s.midY, width: w / 2, height: h / 2)
        case "top-right": return CGRect(x: s.midX, y: s.midY, width: w / 2, height: h / 2)
        case "bottom-left": return CGRect(x: s.minX, y: s.minY, width: w / 2, height: h / 2)
        case "bottom-right": return CGRect(x: s.midX, y: s.minY, width: w / 2, height: h / 2)
        case "max": return s
        case "almost": return s.insetBy(dx: w * 0.05, dy: h * 0.05)
        case "center":
            let size = CGSize(width: min(current.width, w), height: min(current.height, h))
            return CGRect(x: s.midX - size.width / 2, y: s.midY - size.height / 2, width: size.width, height: size.height)
        default: return nil
        }
    }

    // MARK: Accessibility helpers

    private static func attr<T>(_ e: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    /// A window's frame in Cocoa coordinates (AX uses a top-left origin on the main display).
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let p: AXValue = attr(window, kAXPositionAttribute), let s: AXValue = attr(window, kAXSizeAttribute) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p, .cgPoint, &pos)
        AXValueGetValue(s, .cgSize, &size)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: pos.x, y: top - pos.y - size.height, width: size.width, height: size.height)
    }

    static func setFrame(_ window: AXUIElement, _ f: CGRect) {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        var pos = CGPoint(x: f.minX, y: top - f.maxY), size = f.size
        // Size, move, size again: a window clamped by its old screen's edges gets its full size.
        if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) }
        if let v = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v) }
        if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) }
    }

    private static func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.5)
        if let w: AXUIElement = attr(ax, kAXFocusedWindowAttribute) { return w }
        if let w: AXUIElement = attr(ax, kAXMainWindowAttribute) { return w }
        return (attr(ax, kAXWindowsAttribute) as [AXUIElement]?)?.first
    }

    private static var previous: [CFHashCode: CGRect] = [:]

    /// Arranges the window of the app you were in (the launcher must have closed first).
    static func arrange(_ layout: String) -> String? {
        guard AXIsProcessTrusted() else { return "Arranging windows needs Accessibility access for AINCRAD." }
        guard let app = targetApp(), let window = focusedWindow(of: app), let current = frame(of: window) else {
            return "No window to arrange."
        }
        let screens = NSScreen.screens
        let center = CGPoint(x: current.midX, y: current.midY)
        let screen = screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? screens[0]
        let key = CFHash(window)
        var target: CGRect?
        switch layout {
        case "restore":
            target = previous[key]
        case "next-display":
            guard screens.count > 1, let i = screens.firstIndex(of: screen) else { return "Only one display." }
            let next = screens[(i + 1) % screens.count].visibleFrame, from = screen.visibleFrame
            // Same relative place and size on the other display.
            let rx = (current.minX - from.minX) / from.width, ry = (current.minY - from.minY) / from.height
            let w = min(current.width / from.width * next.width, next.width), h = min(current.height / from.height * next.height, next.height)
            target = CGRect(x: next.minX + rx * next.width, y: next.minY + ry * next.height, width: w, height: h)
        default:
            target = frame(for: layout, in: screen.visibleFrame, current: current)
        }
        guard let target else { return layout == "restore" ? "Nothing to restore." : nil }
        if layout != "restore" { previous[key] = current }
        setFrame(window, target)
        app.activate(options: [])
        Log.info("windows: \(app.localizedName ?? "?") → \(layout)")
        return nil
    }

    // MARK: Switcher

    struct Entry { let app: NSRunningApplication; let title: String; let minimized: Bool; let window: AXUIElement }

    /// Every titled window of every regular app (slow-ish: asks each app; call off the main thread).
    static func allWindows() -> [Entry] {
        guard AXIsProcessTrusted() else { return [] }
        var out: [Entry] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 0.3)
            for w in (attr(ax, kAXWindowsAttribute) as [AXUIElement]?) ?? [] {
                let role: String? = attr(w, kAXSubroleAttribute)
                guard role == nil || role == (kAXStandardWindowSubrole as String),
                      let title: String = attr(w, kAXTitleAttribute), !title.isEmpty else { continue }
                out.append(Entry(app: app, title: title, minimized: (attr(w, kAXMinimizedAttribute) as Bool?) ?? false, window: w))
            }
        }
        return out
    }

    static func raise(_ e: Entry) {
        if e.minimized { AXUIElementSetAttributeValue(e.window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        AXUIElementPerformAction(e.window, kAXRaiseAction as CFString)
        e.app.activate(options: [])
    }
}

/// The launcher's Windows menu: switch to any window, arrange the current one, workspaces.
final class WindowMenu {
    static let shared = WindowMenu()
    var onUpdate: ((String) -> Void)?
    private var cache: (time: Date, entries: [WindowControl.Entry])?
    private var loading = false
    private var raiseTable: [String: WindowControl.Entry] = [:]

    static func root() -> MenuItem {
        MenuItem(id: "windows:root", name: "Windows", icon: "sf:macwindow.on.rectangle", children: [
            MenuItem(id: "windows:switch", name: "Switch To", icon: "sf:rectangle.stack.fill", provider: "windows:all",
                     description: "Every open window in every app. Minimized ones come back when you choose them."),
            MenuItem(id: "windows:arrange", name: "Arrange Window", icon: "sf:rectangle.split.2x1.fill", provider: "windows:layouts",
                     description: "Halves, thirds, quarters and more for the window you were just using."),
            MenuItem(name: "Workspaces", icon: "sf:rectangle.3.group.fill", provider: "productivity:workspaces"),
        ], description: "Switch, arrange and save windows.")
    }

    func children(_ provider: String) -> [MenuItem] {
        switch provider {
        case "windows:layouts":
            let groups = ["Halves", "Thirds", "Quarters", "Size"]
            return groups.map { g in
                MenuItem(id: "windows:group:" + g, name: g, icon: g == "Halves" ? "sf:rectangle.split.2x1" : g == "Thirds" ? "sf:rectangle.split.3x1"
                         : g == "Quarters" ? "sf:rectangle.split.2x2" : "sf:arrow.up.left.and.arrow.down.right",
                         children: WindowControl.layouts.filter { $0.group == g }.map {
                             MenuItem(id: "windows:layout:" + $0.id, name: $0.title, icon: $0.icon, action: .builtin("windows:arrange:" + $0.id))
                         })
            }
        case "windows:all":
            if let c = cache, Date().timeIntervalSince(c.time) < 5 { return items(c.entries) }
            load()
            return [MenuItem(id: "windows:loading", name: "Finding windows…", icon: "sf:hourglass")]
        default: return []
        }
    }

    private func load() {
        guard !loading else { return }
        guard AXIsProcessTrusted() else { cache = (Date(), []); return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = WindowControl.allWindows()
            DispatchQueue.main.async {
                self?.loading = false
                self?.cache = (Date(), entries)
                self?.onUpdate?("windows:all")
            }
        }
    }

    /// One row per window; apps with several windows get a submenu.
    private func items(_ entries: [WindowControl.Entry]) -> [MenuItem] {
        guard !entries.isEmpty else { return [MenuItem(id: "windows:none", name: AXIsProcessTrusted() ? "No open windows" : "Needs Accessibility access", icon: "sf:macwindow")] }
        raiseTable = [:]
        var byApp: [(NSRunningApplication, [WindowControl.Entry])] = []
        for e in entries {
            if let i = byApp.firstIndex(where: { $0.0 == e.app }) { byApp[i].1.append(e) } else { byApp.append((e.app, [e])) }
        }
        func row(_ e: WindowControl.Entry, _ i: Int, name: String) -> MenuItem {
            let key = "\(e.app.processIdentifier)-\(i)-\(e.title.hashValue)"
            raiseTable[key] = e
            return MenuItem(id: "windows:w:" + key, name: name + (e.minimized ? "  (minimized)" : ""),
                            icon: e.app.bundleURL.map { "app:" + $0.path } ?? "sf:macwindow", action: .builtin("windows:raise:" + key))
        }
        return byApp.map { app, list in
            let appName = app.localizedName ?? "App"
            if list.count == 1 { return row(list[0], 0, name: "\(appName) — \(list[0].title)") }
            return MenuItem(id: "windows:app:\(app.processIdentifier)", name: "\(appName) (\(list.count))",
                            icon: app.bundleURL.map { "app:" + $0.path } ?? "sf:macwindow",
                            children: list.enumerated().map { row($0.element, $0.offset, name: $0.element.title) })
        }
    }

    /// "windows:arrange:<layout>" / "windows:raise:<key>". Runs after the launcher closes.
    func perform(_ builtin: String) -> String? {
        let parts = builtin.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }
        switch parts[1] {
        case "arrange": return WindowControl.arrange(parts[2])
        case "raise":
            if let e = raiseTable[parts[2]] { WindowControl.raise(e) }
            return nil
        default: return nil
        }
    }

    /// Typed in the launcher: "window left", "window third right", "window max"…
    static func commandResults(_ raw: String) -> [MenuItem] {
        let q = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.hasPrefix("window ") || q.hasPrefix("win ") else { return [] }
        let term = q.split(separator: " ", maxSplits: 1).last.map(String.init) ?? ""
        return WindowControl.layouts.filter { term.isEmpty || $0.title.lowercased().contains(term) || $0.id.replacingOccurrences(of: "-", with: " ").contains(term) }
            .prefix(6).map { MenuItem(id: "windows:cmd:" + $0.id, name: "Window: " + $0.title, icon: $0.icon, action: .builtin("windows:arrange:" + $0.id)) }
    }
}
