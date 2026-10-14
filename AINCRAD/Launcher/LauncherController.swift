import AppKit

final class LauncherController: NSObject, NSWindowDelegate, MenuViewDelegate {
    private let store: ConfigStore
    private let builtin: (String) -> Void
    private let productivity: ProductivityCenter
    private var panel: LauncherPanel?
    private var menuView: MenuView?
    private var clickMonitor: Any?
    private let probe = FrameProbe()
    private var appsCache: (time: Date, items: [MenuItem])?
    private var categoriesCache: (time: Date, items: [MenuItem])?
    private var gamesCache: (time: Date, items: [MenuItem])?
    private(set) var isOpen = false
    let recents: RecentApps
    private var screenName = ""
    private var runningIDs: Set<String>?
    /// Dynamic lists contributed by extensions ("ext:<id>/<menu>").
    var extensionMenu: ((String) -> [MenuItem]?)?
    /// Unsaved menu/theme shown by the editor's Preview button; cleared when the launcher closes.
    private var previewMenu: MenuFile?
    private var previewTheme: Theme?

    init(store: ConfigStore, productivity: ProductivityCenter, builtin: @escaping (String) -> Void) {
        self.store = store
        self.productivity = productivity
        self.builtin = builtin
        recents = RecentApps(directory: store.directory)
        super.init()
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid(), front.activationPolicy == .regular { lastOtherApp = front }
        // Remember the last app the user was in, however the launcher gets opened (a URL or a
        // widget click can make AINCRAD frontmost before open() runs).
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != getpid(), app.activationPolicy == .regular else { return }
            self?.lastOtherApp = app
        }
    }
    private var lastOtherApp: NSRunningApplication?

    enum Origin { case shortcut, gesture(CGPoint), point(NSPoint) }

    /// Reports open/close so the gesture tap can stand aside while the launcher handles the mouse.
    var onOpenChanged: ((Bool) -> Void)?
    /// The app that was frontmost when the launcher opened.
    private(set) var previousApp: NSRunningApplication?
    /// Reports chosen items by name (script "when menu item … is chosen" blocks).
    var onItemChosen: ((String) -> Void)?

    func toggle() { isOpen ? close("toggle") : open() }

    func open(from origin: Origin = .shortcut) {
        guard !isOpen else { return }
        let t0 = CACurrentMediaTime()
        var mouse = NSEvent.mouseLocation
        if case .gesture(let p) = origin, store.settings.placement == "gestureStart" {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            mouse = NSPoint(x: p.x, y: primaryHeight - p.y)
        }
        var fromWidget = false
        if case .point(let p) = origin { mouse = p; fromWidget = true }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        if store.settings.placement == "center", !fromWidget { mouse = NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY) }
        let (panel, view) = ensurePanel()
        screenName = screen.localizedName
        runningIDs = nil
        SoundPlayer.shared.enabled = store.settings.soundsEnabled
        var theme = previewTheme ?? store.theme
        if previewTheme == nil, let accent = store.settings.displayAccents[screen.localizedName] {
            theme.colors.accent = accent
        }
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            theme = theme.highContrast()
        }
        SoundPlayer.shared.sounds = theme.sounds
        panel.setFrame(screen.frame, display: false)
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        let cursor = CGPoint(x: mouse.x - screen.frame.minX, y: screen.frame.maxY - mouse.y)
        view.playerName = store.settings.playerName
        let vf = screen.visibleFrame, sf = screen.frame
        view.safeArea = CGRect(x: vf.minX - sf.minX, y: sf.maxY - vf.maxY, width: vf.width, height: vf.height)
        // The shell's top bar and dock replace the HUD's player bar and clock, so keep the frame clear of them.
        view.shellOn = store.settings.shellModeEnabled
        if view.shellOn, let a = view.safeArea {
            let top = ShellController.barHeight(for: screen) - a.minY, bottom = ShellController.dockHeight + 6
            view.safeArea = CGRect(x: a.minX, y: a.minY + top, width: a.width, height: a.height - top - bottom)
        }
        let t1 = CACurrentMediaTime()
        var items = (previewMenu ?? store.menu).root
        if previewMenu == nil { items.insert(productivity.rootMenu(), at: 0) }
        view.present(items: items, cursor: cursor, theme: theme, motion: motion(theme), scale: screen.backingScaleFactor)
        let t2 = CACurrentMediaTime()
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == getpid() || front?.activationPolicy != .regular ? lastOtherApp : front
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        let t3 = CACurrentMediaTime()
        isOpen = true
        onOpenChanged?(true)
        // A launcher opened from a mouse/touch gesture can otherwise receive that same
        // physical click through the global monitor and close in the very same frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self, self.isOpen, self.clickMonitor == nil else { return }
            self.clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.close("click in another app")
            }
        }
        CATransaction.flush()
        let t4 = CACurrentMediaTime()
        Log.info(String(format: "open on \"%@\" %.0fx%.0f@%.0fx: built+committed in %.1f ms (setup %.1f, build %.1f, show %.1f, commit %.1f)",
                        screen.localizedName, screen.frame.width, screen.frame.height, screen.backingScaleFactor,
                        (t4 - t0) * 1000, (t1 - t0) * 1000, (t2 - t1) * 1000, (t3 - t2) * 1000, (t4 - t3) * 1000))
        probe.run(on: screen, label: "open")
    }

    func close(_ reason: String) {
        guard isOpen else { return }
        isOpen = false
        searchEngine.cancel()
        previewMenu = nil
        previewTheme = nil
        onOpenChanged?(false)
        Log.info("close: \(reason)")
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        menuView?.dismiss { [weak self] in
            guard let self, !self.isOpen else { return }
            self.panel?.orderOut(nil)
        }
    }

    /// Pays first-open costs (panel, window surface, fonts, symbol rasterising, app scan) at launch
    /// with the panel invisible and click-through, so the first real open is as fast as later ones.
    func prewarm() {
        refreshApps()
        guard !isOpen, let screen = NSScreen.main else { return }
        SoundPlayer.shared.enabled = store.settings.soundsEnabled
        SoundPlayer.shared.sounds = store.theme.sounds
        SoundPlayer.shared.prewarm()
        let t0 = CACurrentMediaTime()
        let (panel, view) = ensurePanel()
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.setFrame(screen.frame, display: false)
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.muted = true
        view.present(items: [productivity.rootMenu()] + store.menu.root, cursor: CGPoint(x: screen.frame.width / 2, y: screen.frame.height / 2),
                     theme: store.theme, motion: motion(), scale: screen.backingScaleFactor)
        panel.orderFrontRegardless()
        CATransaction.flush()
        view.dismiss {}
        view.muted = false
        panel.orderOut(nil)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        Log.info(String(format: "prewarm took %.1f ms", (CACurrentMediaTime() - t0) * 1000))
    }

    private func refreshApps() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let t0 = CACurrentMediaTime()
            let items = AppScanner.scan()
            let categories = AppScanner.categorized()
            let games = GameLibrary.menu(GameLibrary.scan())
            DispatchQueue.main.async {
                self?.appsCache = (Date(), items)
                self?.categoriesCache = (Date(), categories)
                self?.gamesCache = (Date(), games)
                Log.info(String(format: "scanned %d apps in %.1f ms (background)", items.count, (CACurrentMediaTime() - t0) * 1000))
            }
        }
    }

    func preview(menu: MenuFile, theme: Theme?) {
        if isOpen { close("preview") }
        previewMenu = menu
        previewTheme = theme
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.open() }
    }

    /// Runs an item directly (item shortcuts), with the same bookkeeping as choosing it in the menu.
    func run(_ item: MenuItem) {
        guard let action = item.action else { return }
        if isOpen { close("item shortcut") }
        Log.info("item shortcut: \(item.name)")
        ActionRunner.run(action, builtin: builtin)
        if case .app(let t) = action, let url = ActionRunner.appURL(t) { recents.note(url.path) }
    }

    func handleKey(named name: String) {
        menuView?.handleKey(named: name)
    }

    private func ensurePanel() -> (LauncherPanel, MenuView) {
        if let panel, let menuView { return (panel, menuView) }
        let p = LauncherPanel()
        let v = MenuView(frame: .zero)
        v.delegate = self
        v.isItemVisible = { [weak self] in self?.isVisible($0) ?? $0.isVisible }
        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.addSubview(v)
        v.autoresizingMask = [.width, .height]
        p.contentView = root
        p.delegate = self
        panel = p
        menuView = v
        return (p, v)
    }

    /// `hidden` plus `visibleWhen` conditions, evaluated against the display being opened on.
    func isVisible(_ item: MenuItem) -> Bool {
        guard item.isVisible else { return false }
        guard let c = item.visibleWhen else { return true }
        if let d = c.display, d.caseInsensitiveCompare(screenName) != .orderedSame { return false }
        if c.appRunning != nil || c.appNotRunning != nil {
            let running = runningIDs ?? Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            runningIDs = running
            if let a = c.appRunning, !running.contains(a) { return false }
            if let a = c.appNotRunning, running.contains(a) { return false }
        }
        if let a = c.appInstalled, NSWorkspace.shared.urlForApplication(withBundleIdentifier: a) == nil { return false }
        return true
    }

    private func motion(_ theme: Theme? = nil) -> Motion {
        let setting = store.settings.reducedMotion
        let reduced = setting == "on" || (setting == "system" && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        return Motion(spec: (theme ?? store.theme).animation, reduced: reduced)
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        close("lost key focus")
    }

    // MARK: MenuViewDelegate

    func menuView(_ view: MenuView, activate item: MenuItem) {
        close("activated \(item.name)")
        onItemChosen?(item.name)
        if let action = item.action {
            ActionRunner.run(action, builtin: builtin)
            productivity.record(item.id)
            if case .app(let t) = action, let url = ActionRunner.appURL(t) { recents.note(url.path) }
        }
    }

    func menuView(_ view: MenuView, childrenOf item: MenuItem) -> [MenuItem] {
        guard let provider = item.provider else { return item.children ?? [] }
        switch provider {
        case "applications":
            // Serve the cached list instantly and refresh it off the main thread when stale.
            if let cache = appsCache {
                if Date().timeIntervalSince(cache.time) > 120 { refreshApps() }
                return cache.items
            }
            let items = AppScanner.scan()
            appsCache = (Date(), items)
            return items
        case "recentApps":
            return recents.items()
        case "games":
            if let cache = gamesCache {
                if Date().timeIntervalSince(cache.time) > 120 { refreshApps() }
                return cache.items
            }
            // Normally ready from the launch-time scan; never scan on the main thread.
            refreshApps()
            return [MenuItem(id: "games:loading", name: "Looking for games…", icon: "sf:hourglass")]
        case "appCategories":
            if let cache = categoriesCache {
                if Date().timeIntervalSince(cache.time) > 120 { refreshApps() }
                return cache.items
            }
            let items = AppScanner.categorized()
            categoriesCache = (Date(), items)
            return items
        case "productivity:clipboard": return productivity.clipboardMenu()
        case "productivity:captures": return productivity.captureMenu()
        case "productivity:workspaces": return productivity.workspacesMenu()
        case "productivity:system": return productivity.systemMenu()
        case "productivity:suggestions": return productivity.suggestions()
        case "productivity:context": return productivity.contextMenu()
        case let p where p.hasPrefix("ext:"):
            return extensionMenu?(p) ?? []
        default:
            Log.error("unknown provider \"\(provider)\"")
            return item.children ?? []
        }
    }

    func menuViewRequestsClose(_ view: MenuView, reason: String) {
        close(reason)
    }

    // MARK: Context actions

    private var favoritesID: String? {
        store.menu.root.first { $0.name.caseInsensitiveCompare("Favorites") == .orderedSame && $0.children != nil }?.id
    }

    private func runningApp(_ item: MenuItem) -> NSRunningApplication? {
        guard case .app(let t) = item.action, let url = ActionRunner.appURL(t) else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
    }

    /// The file an app or folder item points at, for the dock's Add/Remove actions.
    private func dockPath(_ item: MenuItem) -> String? {
        switch item.action {
        case .app(let t): return ActionRunner.appURL(t)?.standardizedFileURL.path
        case .open(let p):
            let path = URL(fileURLWithPath: (p as NSString).expandingTildeInPath).standardizedFileURL.path
            var dir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue ? path : nil
        default: return nil
        }
    }

    func menuView(_ view: MenuView, contextActionsFor item: MenuItem) -> [MenuView.ContextAction] {
        typealias A = MenuView.ContextAction
        var out: [A] = []
        if item.action != nil { out.append(A(id: "open", title: "Open", symbol: "arrow.up.forward.app.fill")) }
        switch item.action {
        case .app:
            out.append(A(id: "finder", title: "Show in Finder", symbol: "folder.fill"))
            if let app = runningApp(item) { out.append(A(id: "quit", title: "Quit \(app.localizedName ?? item.name)", symbol: "xmark.circle.fill")) }
        case .open:
            out.append(A(id: "finder", title: "Show in Finder", symbol: "folder.fill"))
            out.append(A(id: "copy", title: "Copy Path", symbol: "doc.on.doc.fill"))
        case .url:
            out.append(A(id: "copy", title: "Copy Link", symbol: "link"))
        default: break
        }
        if let path = dockPath(item) {
            out.append(DockStore.shared.contains(path)
                ? A(id: "undock", title: "Remove from Dock", symbol: "dock.arrow.down.rectangle")
                : A(id: "dock", title: "Add to Dock", symbol: "dock.arrow.up.rectangle"))
        }
        let inMenu = MenuTree.find(item.id, in: store.menu.root) != nil
        let inFavorites = favoritesID.flatMap { MenuTree.find($0, in: store.menu.root)?.children?.contains { $0.id == item.id } } ?? false
        if inFavorites {
            out.append(A(id: "unfav", title: "Remove from Favorites", symbol: "star.slash.fill"))
        } else if item.action != nil {
            out.append(A(id: "fav", title: "Add to Favorites", symbol: "star.fill"))
        }
        if inMenu && !inFavorites { out.append(A(id: "hide", title: "Hide from Menu", symbol: "eye.slash.fill")) }
        return out
    }

    func menuView(_ view: MenuView, perform action: String, on item: MenuItem) {
        func url() -> URL? {
            switch item.action {
            case .app(let t): return ActionRunner.appURL(t)
            case .open(let p): return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            default: return nil
            }
        }
        switch action {
        case "dock":
            if let u = url() { DockStore.shared.add(u) }
        case "undock":
            if let p = dockPath(item) { DockStore.shared.remove(p) }
        case "open":
            menuView(view, activate: item)
        case "finder":
            close("show in finder")
            if let u = url() { NSWorkspace.shared.activateFileViewerSelecting([u]) }
        case "quit":
            runningApp(item)?.terminate()
            Log.info("quit \(item.name) from the launcher")
        case "copy":
            let text: String
            switch item.action {
            case .url(let u): text = u
            case .open(let p): text = (p as NSString).expandingTildeInPath
            default: text = item.name
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case "fav", "unfav", "hide":
            editMenu(action, item)
        default:
            Log.error("unknown context action \(action)")
        }
    }

    /// Favorites / hide edits go straight to menu.json (with a backup), then the menu reloads.
    private func editMenu(_ action: String, _ item: MenuItem) {
        var menu = store.menu
        switch action {
        case "fav":
            var copy = item
            copy.id = UUID().uuidString
            copy.children = item.children
            if let fav = favoritesID {
                MenuTree.insert(copy, inside: fav, in: &menu.root)
            } else {
                menu.root.insert(MenuItem(name: "Favorites", icon: "sf:star.fill", children: [copy]), at: 0)
            }
        case "unfav":
            MenuTree.remove(item.id, in: &menu.root)
        case "hide":
            guard var hidden = MenuTree.find(item.id, in: menu.root) else { return }
            hidden.hidden = true
            MenuTree.replace(hidden, in: &menu.root)
        default: return
        }
        do {
            try store.saveMenu(menu)
            Log.info("menu: \(action) \(item.name)")
        } catch {
            Log.error("menu edit failed: \(error.localizedDescription)")
        }
        close("menu edited")
        builtin("reload")
    }

    private let searchEngine = SearchEngine()

    func menuView(_ view: MenuView, search query: String, more: @escaping ([MenuItem]) -> Void) -> [MenuItem] {
        guard !query.isEmpty else { searchEngine.cancel(); return [] }
        let apps = appsCache?.items ?? {
            let items = AppScanner.scan()
            appsCache = (Date(), items)
            return items
        }()
        let menu = (previewMenu ?? store.menu).root.filter(isVisible)
        searchEngine.files(query, completion: more)
        return productivity.commandResults(query) + SearchEngine.instant(query, apps: apps, menu: menu)
    }

    func menuViewDidOpenColumn(_ view: MenuView) {
        if let screen = panel?.screen { probe.run(on: screen, label: "column") }
    }
}
