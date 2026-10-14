import AppKit

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

    private static let clockFormat: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM  ·  h:mm a"
        return df
    }()

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
        dv.onFolder = { [weak self] app, rect in self?.showFolder(app, from: rect) }
        dv.onMove = { from, to in DockStore.shared.move(from: from, to: to) }
        dv.onRemove = { app in DockStore.shared.remove(app.url.standardizedFileURL.path) }
        dv.onDrop = { urls, index in
            for (offset, url) in urls.enumerated() { DockStore.shared.add(url, at: index + offset) }
        }
        if DockStore.shared.onChange == nil {
            DockStore.shared.onChange = { [weak self] in self?.refresh() }
        }
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
            // Fade the layers, not the windows: Core Animation runs it off the main thread.
            for panel in panels where currentlyShown(panel) {
                guard let layer = panel.contentView?.layer else { continue }
                layer.removeAnimation(forKey: "out")
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = 0.18
                layer.add(fade, forKey: "in")
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
        let panels = bars.map(\.panel) + [dockPanel].compactMap({ $0 })
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard self?.visible != true else { return }
            for panel in panels {
                panel.orderOut(nil)
                panel.contentView?.layer?.removeAnimation(forKey: "out")
            }
        }
        for panel in panels {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.14
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            panel.contentView?.layer?.add(fade, forKey: "out")
        }
        CATransaction.commit()
    }

    // MARK: Edges and full screen

    private func updateModes(animated: Bool) {
        guard visible else { return }
        // The window-list scan costs several ms; only always-on mode (launcher closed) needs it.
        let fullScreen = alwaysOn && !launcherOpen ? fullScreenDisplays() : []
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
        let clock = ShellController.clockFormat.string(from: Date())
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

    /// Runs a dock edit right away, keeping the launcher open so you can keep arranging.
    private func performEdit(_ node: AXMenus.Node) {
        SoundPlayer.shared.play(.select)
        AXMenus.press(node)
    }

    /// Click on a dock folder: its newest items (like the Downloads stack), read off the main thread.
    private func showFolder(_ app: ShellApp, from rect: NSRect) {
        guard let dock = dockPanel, let screen = dock.screen else { return }
        if menus.isOpen { menus.hide(); return }
        let folder = app.url
        let sort = DockStore.shared.items.first { $0.path == folder.standardizedFileURL.path }?.sort ?? "name"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let nodes = ShellController.folderNodes(folder, sort: sort)
            DispatchQueue.main.async {
                guard let self, self.visible else { return }
                self.menus.show(nodes, title: app.name, anchor: rect, screen: screen, theme: self.theme, level: dock.level,
                                rising: true) { [weak self] node in self?.perform(node) }
            }
        }
    }

    /// A folder's items as menu nodes: subfolders become submenus (two levels deep), files and
    /// apps (aliases too) open on click, then "Open in Finder". Sorted by name, or newest first.
    static func folderNodes(_ folder: URL, sort: String = "name", depth: Int = 0, limit: Int = 40) -> [AXMenus.Node] {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey, .isDirectoryKey, .isPackageKey, .isHiddenKey]
        let open = AXMenus.Node.action("Open in Finder", icon: "sf:folder") { NSWorkspace.shared.open(folder) }
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            // Most likely macOS privacy protection (Downloads, Documents, Desktop) that hasn't been allowed yet.
            return [AXMenus.Node(title: "Couldn't read this folder", enabled: false),
                    .action("Open Privacy Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                    }, .separatorLine, open]
        }
        func values(_ u: URL) -> URLResourceValues? { try? u.resourceValues(forKeys: Set(keys)) }
        // Finder's custom-icon files ("Icon\r") are hidden by flag, not by a leading dot.
        let visible = entries.filter { values($0)?.isHidden != true && $0.lastPathComponent != "Icon\r" }
        let sorted: [URL] = sort == "added"
            ? visible.sorted { (values($0)?.addedToDirectoryDate ?? .distantPast) > (values($1)?.addedToDirectoryDate ?? .distantPast) }
            : visible.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var nodes: [AXMenus.Node] = []
        for u in sorted.prefix(limit) {
            let v = values(u)
            let name = u.pathExtension == "app" ? u.deletingPathExtension().lastPathComponent : FileManager.default.displayName(atPath: u.path)
            if v?.isDirectory == true && v?.isPackage != true && depth < 2 {
                nodes.append(.submenu(name, icon: "app:" + u.path, folderNodes(u, sort: sort, depth: depth + 1, limit: limit)))
            } else {
                nodes.append(.action(name, icon: "app:" + u.path) { NSWorkspace.shared.open(u) })
            }
        }
        if nodes.isEmpty { nodes.append(AXMenus.Node(title: "Empty", enabled: false)) }
        if sorted.count > limit {
            nodes.append(.action("\(sorted.count - limit) more in Finder…") { NSWorkspace.shared.open(folder) })
        }
        return nodes + [.separatorLine, open]
    }

    /// Right-click on a dock app: its windows, then Open/Show, Show in Finder, Hide and Quit.
    private func showContext(for app: ShellApp, from rect: NSRect) {
        guard let dock = dockPanel, let screen = dock.screen else { return }
        if menus.isOpen { menus.hide(); return }
        let running = app.bundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        var nodes: [AXMenus.Node] = []
        let path = app.url.standardizedFileURL.path
        let store = DockStore.shared
        let pinnedIndex = store.items.firstIndex { $0.path == path }
        var edits: [AXMenus.Node] = []
        if let i = pinnedIndex {
            edits.append(.action("Move Left", enabled: i > 0) { store.move(from: i, to: i - 1) })
            edits.append(.action("Move Right", enabled: i < store.items.count - 1) { store.move(from: i, to: i + 1) })
            edits.append(.action("Remove from Dock") { store.remove(path) })
        } else {
            edits.append(.action("Keep in Dock") { store.add(app.url) })
        }
        if app.folder {
            let sort = pinnedIndex.flatMap { store.items[$0].sort } ?? "name"
            nodes = [.action("Open") { NSWorkspace.shared.open(app.url) },
                     .action("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) },
                     .separatorLine,
                     .action("Sort by Name", checked: sort == "name") { store.setSort(path, "name") },
                     .action("Sort by Date Added", checked: sort == "added") { store.setSort(path, "added") },
                     .separatorLine] + edits
            edits += [nodes[3], nodes[4]]
            let editTitles = Set(edits.map(\.title))
            menus.show(nodes, title: app.name, anchor: rect, screen: screen, theme: theme, level: dock.level, rising: true) { [weak self] node in
                editTitles.contains(node.title) ? self?.performEdit(node) : self?.perform(node)
            }
            return
        }
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
        nodes.append(.separatorLine)
        nodes += edits
        if let running {
            nodes.append(.separatorLine)
            nodes.append(.action(running.isHidden ? "Unhide" : "Hide") { running.isHidden ? running.unhide() : running.hide() })
            nodes.append(.action("Quit") { running.terminate() })
        }
        let editTitles = Set(edits.map(\.title))
        menus.show(nodes, title: app.name, anchor: rect, screen: screen, theme: theme, level: dock.level, rising: true) { [weak self] node in
            // Dock edits happen in place (the launcher stays open); the rest act on the app.
            editTitles.contains(node.title) ? self?.performEdit(node) : self?.perform(node)
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

    /// The dock's own pinned apps and folders (DockStore), skipping ones that no longer exist.
    private func dockApps() -> [ShellApp] {
        DockStore.shared.items.compactMap { item in
            guard FileManager.default.fileExists(atPath: item.path) else { return nil }
            let url = item.url
            return ShellApp(name: FileManager.default.displayName(atPath: item.path), url: url,
                            bundleID: item.isFolder ? nil : Bundle(url: url)?.bundleIdentifier, pinned: true, folder: item.isFolder)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
}
