import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ConfigStore()
    private lazy var productivity = ProductivityCenter(directory: store.directory)
    private lazy var commandDeck = CommandDeckController(productivity: productivity)
    private let shell = ShellController()
    private var launcher: LauncherController?
    private var hotKey: HotKey?
    private var hotKeyProblem: String?
    private let itemShortcuts = ItemShortcuts()
    private var hotKeysSuspended = false
    private var statusItem: NSStatusItem?
    private var gesture: GestureMonitor?
    private var touch: TouchMonitor?
    private let notes = NotificationMirror()
    private let bubbles = NotificationBubbles()
    private var notesProblem: String?
    private var gestureProblem: String?
    private var permissionTimer: Timer?
    private var settingsWindow: SettingsWindowController?
    private var studioWindow: StudioWindowController?
    private var widgets: WidgetManager?
    private var extensions: ExtensionManager?
    private let scripts = ScriptRuntime()
    private lazy var scriptHost = AppScriptHost(store: store)
    private lazy var guardian = LaunchGuard(directory: ConfigStore.baseDirectory)
    private var safeMode: Bool { guardian.safeMode }
    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests host inside the app; don't grab the hotkey or the menu bar there.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        // One AINCRAD at a time: a second copy would fight the first over hotkeys and the gesture.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != getpid() }
        if !others.isEmpty {
            Log.info("another AINCRAD is already running (pid \(others[0].processIdentifier)); quitting this copy")
            NSApp.terminate(nil)
            return
        }
        installMainMenu()
        registerBundledFonts()
        guardian.begin()
        // Logout and `kill` send SIGTERM; route it through a normal quit so state is saved.
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { NSApp.terminate(nil) }
        term.resume()
        termSource = term
        store.load()
        productivity.enabled = store.settings.productivityEnabled
        productivity.clipboardLimit = store.settings.clipboardHistoryLimit
        productivity.start()
        launcher = LauncherController(store: store, productivity: productivity) { [weak self] in self?.runBuiltin($0) }
        launcher?.onOpenChanged = { [weak self] open in
            self?.gesture?.setLauncherOpen(open)
            self?.touch?.setLauncherOpen(open)
            // The bar, dock and HUD widgets fade in over ~0.2 s, so showing them a frame after the
            // menu costs nothing visible and keeps their window ordering (~15 ms) off the open path.
            let showShell = { [weak self] in
                guard let self, self.launcher?.isOpen == open else { return }
                self.shell.playerName = self.store.settings.playerName
                self.shell.targetApp = self.launcher?.previousApp
                self.shell.setLauncherOpen(open, enabled: self.store.settings.shellModeEnabled && !self.safeMode,
                                           hideMenuBar: false, hideDock: false, theme: self.store.theme)
                self.widgets?.setHUD(on: open ? NSApp.windows.first(where: { $0 is LauncherPanel })?.screen : nil)
            }
            open ? DispatchQueue.main.async(execute: showShell) : showShell()
            if open { self?.scripts.launcherOpened() }
        }
        launcher?.onItemChosen = { [weak self] name in
            self?.scripts.itemChosen(name)
            BattleLog.shared.add("Used \(name)", symbol: "hand.tap.fill")
            ExpStore.shared.gain(10)
        }
        BattleLog.shared.start()
        ExpStore.shared.start()
        launcher?.recents.start()
        commandDeck.openLauncher = { [weak self] in self?.launcher?.open() }
        shell.openLauncher = { [weak self] in self?.launcher?.open() }
        shell.closeLauncher = { [weak self] in self?.launcher?.close("app menu") }
        commandDeck.theme = store.theme
        if store.settings.commandDeckEnabled { commandDeck.show() }
        let ext = ExtensionManager(store: store)
        if !safeMode {
            ext.seedBundledPlugins()
            ext.load()
        }
        extensions = ext
        launcher?.extensionMenu = { [weak ext] in ext?.menuItems($0) }
        let w = WidgetManager(store: store)
        w.extraEntries = { [weak ext] in ext?.widgetPresets ?? [] }
        w.onOpenLauncher = { [weak self] rect in self?.launcher?.open(from: .point(NSPoint(x: rect.midX, y: rect.midY))) }
        widgets = w
        if !safeMode {
            w.load()
            w.addHUDStarterIfNeeded()
        }
        scriptHost.openLauncherAction = { [weak self] in self?.launcher?.open() }
        scriptHost.reloadAction = { [weak self] in self?.reload() }
        scriptHost.widgetsChanged = { [weak self] in self?.widgets?.rebuildAll() }
        scripts.host = scriptHost
        loadScripts()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        applyActivation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.launcher?.prewarm()
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        Log.info("AINCRAD \(version) started\(safeMode ? " in SAFE MODE" : "") pid=\(getpid()) screens=\(NSScreen.screens.map(\.localizedName))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        gesture?.stop()
        touch?.stop()
        notes.stop()
        launcher?.recents.save()
        productivity.stop()
        commandDeck.hide()
        shell.setLauncherOpen(false, enabled: false, hideMenuBar: false, hideDock: false, theme: store.theme)
        // Never leave the user without a menu bar and Dock once AINCRAD is gone.
        SystemChrome.restoreAll()
        guardian.end()
        Log.info("quit")
    }

    /// Opening the app again (Finder, Spotlight, Dock) shows settings, since there's no other window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    /// aincrad://open | close | toggle | reload | settings[/tab] | key/<up|down|left|right|enter|back|escape>
    ///         | widgets/<edit|done|save|show|hide>
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL && url.pathExtension.lowercased() == "aincrad" {
            DispatchQueue.main.async { self.installPackage(url) }
        }
        for url in urls where url.scheme == "aincrad" {
            switch url.host {
            case "open": launcher?.open()
            case "close": launcher?.close("url")
            case "toggle": launcher?.toggle()
            case "reload": reload()
            case "settings": showSettings(tab: SettingsView.Tab(rawValue: url.lastPathComponent))
            case "studio": showStudio(nil)
            case "test-bubble": showBubble(.init(app: "AINCRAD", title: "Message", body: "Welcome to Sword Art Online! This is how notifications will look."))
            case "key": launcher?.handleKey(named: url.lastPathComponent)
            case "widgets":
                switch url.lastPathComponent {
                case "edit": widgets?.setEditing(true)
                case "done": widgets?.setEditing(false)
                case "save": widgets?.save()
                case "show", "hide":
                    store.update { $0.widgetsEnabled = url.lastPathComponent == "show" }
                    widgets?.rebuildAll()
                default: break
                }
            default: Log.error("unknown url \(url.absoluteString)")
            }
        }
    }

    // MARK: Activation

    /// Applies everything settings and the menu control: hotkeys, item shortcuts, gesture, safety flags.
    /// The SAO bar and dock, and (when they replace Apple's) the system-wide menu bar/Dock hiding.
    /// SystemChrome only touches the system when something actually changes, so this is cheap to repeat.
    private func applyShell() {
        let s = store.settings
        let replace = s.shellModeEnabled && s.shellReplaceSystem && !safeMode
        SystemChrome.update(hideDock: (s.hideAppleDock || replace) && !safeMode, coverMenuBar: replace,
                            hideMenuBar: s.hideAppleMenuBar && !safeMode)
        shell.alwaysOn = replace
        shell.revealMenus = s.shellRevealMenus
        shell.playerName = s.playerName
        commandDeck.topInset = replace ? 34 : 0
        shell.setLauncherOpen(launcher?.isOpen == true, enabled: s.shellModeEnabled && !safeMode,
                              hideMenuBar: false, hideDock: false, theme: store.theme)
    }

    private func applyActivation() {
        hotKey = nil
        itemShortcuts.unregister()
        hotKeyProblem = nil
        ActionRunner.allowShell = store.settings.allowShellCommands
        productivity.enabled = store.settings.productivityEnabled
        productivity.clipboardLimit = store.settings.clipboardHistoryLimit
        applyShell()
        commandDeck.theme = store.theme
        store.settings.commandDeckEnabled ? commandDeck.show() : commandDeck.hide()
        if !store.settings.activationPaused && !hotKeysSuspended {
            hotKey = HotKey(store.settings.hotKey) { [weak self] in self?.launcher?.toggle() }
            if hotKey == nil {
                hotKeyProblem = "Shortcut \(HotKey.display(store.settings.hotKey)) unavailable (taken by another app, or unknown key)"
                Log.error(hotKeyProblem!)
            }
            if !safeMode { itemShortcuts.register(store.menu) { [weak self] item in self?.launcher?.run(item) } }
        }
        applyGesture()
        applyNotifications()
        let symbol = store.settings.activationPaused ? "pause.circle" : "circle.circle"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "AINCRAD")
        statusItem?.button?.image?.isTemplate = true
    }

    private func applyGesture() {
        let s = store.settings.gesture
        gestureProblem = nil
        let active = !store.settings.activationPaused && !safeMode

        // Mouse buttons: needs Accessibility, since it holds back right clicks.
        if s.enabled && active {
            if !GestureMonitor.hasPermission {
                gesture?.stop()
                gestureProblem = "Mouse gesture needs Accessibility permission"
            } else {
                if let gesture {
                    gesture.update(s)
                } else {
                    let g = GestureMonitor(settings: s)
                    g.onTrigger = { [weak self] point in self?.launcher?.open(from: .gesture(point)) }
                    gesture = g
                }
                if gesture?.start() == false { gestureProblem = "Mouse gesture could not start (see log)" }
            }
        } else {
            gesture?.stop()
        }

        // Touch surface: read-only, needs no permission.
        if s.touch && active {
            if let touch {
                touch.update(s)
                touch.stop()
            }
            let t = touch ?? TouchMonitor(settings: s)
            t.onTrigger = { [weak self] in self?.launcher?.open() }
            touch = t
            if !t.start() { gestureProblem = "Touch gesture isn't available on this macOS version" }
        } else {
            touch?.stop()
        }
    }

    private func applyNotifications() {
        notesProblem = nil
        bubbles.seconds = store.settings.notificationSeconds
        notes.hideOriginals = store.settings.notificationsHideOriginal
        guard store.settings.notificationBubbles, !safeMode else { return notes.stop() }
        notes.onNote = { [weak self] note in self?.showBubble(note) }
        if !notes.start() { notesProblem = "Notification bubbles need Accessibility permission" }
    }

    private func showBubble(_ note: NotificationMirror.Note) {
        let s = store.settings.reducedMotion
        let reduced = s == "on" || (s == "system" && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        bubbles.show(note, theme: store.theme, reducedMotion: reduced)
        BattleLog.shared.add("\(note.app): \(note.title)", symbol: "bell.fill")
        SoundPlayer.shared.enabled = store.settings.soundsEnabled
        SoundPlayer.shared.play(.open)
    }

    /// Shows the system Accessibility prompt, then starts the gesture as soon as access is granted.
    private func requestGesturePermission() {
        GestureMonitor.requestPermission()
        permissionTimer?.invalidate()
        let deadline = Date().addingTimeInterval(600)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            if GestureMonitor.hasPermission || Date() > deadline {
                t.invalidate()
                self.permissionTimer = nil
                self.applyGesture()
                self.applyNotifications()
                Log.info("accessibility granted=\(GestureMonitor.hasPermission)")
            }
        }
    }

    private func reload() {
        launcher?.close("reload")
        store.load()
        if !safeMode {
            extensions?.load()
            widgets?.rebuildAll()
        }
        loadScripts()
        applyActivation()
    }

    /// (Re)starts scripts of enabled extensions; none run in safe mode.
    private func loadScripts() {
        guard !safeMode, let extensions else { return scripts.stop() }
        scripts.load(extensions.extensions.filter(extensions.isEnabled))
    }

    private func runBuiltin(_ name: String) {
        switch name {
        case "reload": reload()
        case "settings": showSettings()
        case "openConfig": NSWorkspace.shared.activateFileViewerSelecting([store.menuURL])
        case "openLog": NSWorkspace.shared.open(Log.fileURL)
        case "pause": togglePause()
        case "none": break
        case let n where n.hasPrefix("prism:"):
            // Prism Launcher starts an instance by its folder name.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "Prism Launcher", "--args", "--launch", String(n.dropFirst(6))]
            try? p.run()
        case let n where n.hasPrefix("copy:"):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(n.dropFirst(5)), forType: .string)
        case let n where n.hasPrefix("productivity:paste:"):
            productivity.paste(String(n.dropFirst("productivity:paste:".count)))
        case let n where n.hasPrefix("productivity:copyCapture:"):
            productivity.copyCapture(String(n.dropFirst("productivity:copyCapture:".count)))
        case let n where n.hasPrefix("productivity:workspace:"):
            productivity.runWorkspace(String(n.dropFirst("productivity:workspace:".count)))
        case let n where n.hasPrefix("productivity:timer:"):
            if let minutes = Int(n.dropFirst("productivity:timer:".count)) { productivity.startTimer(minutes: minutes) }
        case let n where n.hasPrefix("productivity:captureText:"):
            let encoded = String(n.dropFirst("productivity:captureText:".count))
            productivity.capture(encoded.removingPercentEncoding ?? encoded)
        case let n where n.hasPrefix("productivity:context:copy:"):
            let value = String(n.dropFirst("productivity:context:copy:".count)); productivity.putTextOnClipboard(value.removingPercentEncoding ?? value)
        case let n where n.hasPrefix("productivity:context:uppercase:"):
            let value = String(n.dropFirst("productivity:context:uppercase:".count)); productivity.putTextOnClipboard((value.removingPercentEncoding ?? value).uppercased())
        case let n where n.hasPrefix("productivity:context:lowercase:"):
            let value = String(n.dropFirst("productivity:context:lowercase:".count)); productivity.putTextOnClipboard((value.removingPercentEncoding ?? value).lowercased())
        case "productivity:quitFront":
            NSWorkspace.shared.frontmostApplication?.terminate()
        case let n where n.hasPrefix("productivity:volume:"):
            let mode = String(n.dropFirst("productivity:volume:".count))
            let script: String
            switch mode {
            case "up": script = "set volume output volume ((output volume of (get volume settings)) + 10)"
            case "down": script = "set volume output volume ((output volume of (get volume settings)) - 10)"
            default: script = "set volume output muted not (output muted of (get volume settings))"
            }
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", script]; try? p.run()
        case let n where n.hasPrefix("productivity:window:"):
            productivity.tileFrontWindow(String(n.dropFirst("productivity:window:".count)))
        case "productivity:captureClipboard": productivity.captureClipboard()
        case "productivity:newWorkspace": promptForWorkspace()
        case "productivity:lock":
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"); p.arguments = ["-suspend"]; try? p.run()
        case "quit": NSApp.terminate(nil)
        default: Log.error("unknown builtin \"\(name)\"")
        }
    }

    private func promptForWorkspace() {
        let alert = NSAlert()
        alert.messageText = "Save Current Workspace"
        alert.informativeText = "AINCRAD will remember the applications currently open."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: "My Workspace")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        productivity.saveWorkspace(named: field.stringValue)
    }

    // MARK: Settings window

    private func showSettings(tab: SettingsView.Tab? = nil) {
        if settingsWindow == nil {
            let actions = AppActions(
                applySettings: { [weak self] in self?.applyActivation() },
                reloadAll: { [weak self] in self?.reload() },
                previewMenu: { [weak self] menu, theme in self?.launcher?.preview(menu: menu, theme: theme) },
                suspendHotKeys: { [weak self] on in
                    self?.hotKeysSuspended = on
                    self?.applyActivation()
                },
                requestAccessibility: { [weak self] in self?.requestGesturePermission() },
                hasAccessibility: { GestureMonitor.hasPermission },
                openStudio: { [weak self] ext in self?.showStudio(ext) },
                installPackage: { [weak self] url in self?.installPackage(url) },
                testBubble: { [weak self] in
                    self?.showBubble(.init(app: "AINCRAD", title: "Message", body: "Welcome to Sword Art Online! This is how notifications will look."))
                })
            guard let widgets, let extensions else { return }
            settingsWindow = SettingsWindowController(model: SettingsModel(store: store, actions: actions,
                                                                           widgets: widgets, extensions: extensions))
            settingsWindow?.onClose = { [weak self] in self?.settingsWindow = nil }
            if let model = settingsWindow?.model {
                MainActor.assumeIsolated {
                    model.catalog.installPackage = { [weak self] url in self?.installPackage(url) }
                }
            }
        }
        settingsWindow?.show(tab: tab)
    }

    /// The Extension Studio. With an extension, edits it; without, starts a new one.
    private func showStudio(_ ext: LoadedExtension?) {
        guard let extensions else { return }
        if let studio = studioWindow, ext == nil || studio.model.extID == ext?.id {
            return studio.show()
        }
        if let studio = studioWindow, studio.model.dirty {
            studio.show()
            studio.model.message = "Save or close “\(studio.model.name)” before opening another extension."
            return
        }
        studioWindow?.close()
        let model = StudioModel(store: store, extensions: extensions, runtime: scripts)
        if let ext { model.open(ext) }
        model.onSaved = { [weak self] in self?.reload() }
        let controller = StudioWindowController(model: model)
        controller.onClose = { [weak self, weak controller] in
            if self?.studioWindow === controller { self?.studioWindow = nil }
        }
        studioWindow = controller
        controller.show()
    }

    /// Double-clicked .aincrad file: check it, ask, install switched off, show it in Settings.
    private func installPackage(_ url: URL) {
        guard let extensions else { return }
        do {
            let (folder, m) = try Packages.unpack(url)
            let existing = extensions.extensions.first { $0.id == m.id }
            let alert = NSAlert()
            alert.messageText = existing == nil ? "Install “\(m.name)”?" : "Replace “\(m.name)” \(existing!.manifest.version) with \(m.version)?"
            var info = "\(m.description ?? "")\n\nVersion \(m.version)" + (m.author.map { " by \($0)" } ?? "")
            let perms = (m.permissions ?? []).sorted()
            info += perms.isEmpty ? "\nNeeds no permissions." : "\nAsks for: \(perms.joined(separator: ", ")) (you approve when enabling it)."
            info += "\n\nIt's installed switched off; turn it on in Settings › Extensions."
            alert.informativeText = info
            alert.addButton(withTitle: existing == nil ? "Install" : "Replace")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if let existing { extensions.setEnabled(existing, false) }
            _ = try Packages.install(folder, id: m.id, into: extensions.folder)
            extensions.load()
            loadScripts()
            showSettings(tab: .extensions)
            Log.info("installed package \(m.id) \(m.version)")
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// Rajdhani and Orbitron (SIL OFL, licences in Resources) ship with the app for SAO-style
    /// themes; registered for this process only, so nothing is installed system-wide.
    private func registerBundledFonts() {
        let fonts = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in fonts { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        Log.info("bundled fonts: \(fonts.map { $0.deletingPathExtension().lastPathComponent }.sorted())")
    }

    /// Accessory apps have no menu bar, but key equivalents still route through the main menu,
    /// which is what makes ⌘C/⌘V/⌘A/⌘W work in the settings window.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit AINCRAD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        main.addItem(appItem)
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: Status menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector?, key: String = "", state: Bool = false, to m: NSMenu = menu) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.state = state ? .on : .off
            m.addItem(item)
            return item
        }

        if safeMode {
            let item = NSMenuItem(title: "⚠︎ Safe Mode: \(guardian.reason)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            _ = add("Restart Normally", #selector(restartNormally))
            menu.addItem(.separator())
        }
        _ = add("Open Launcher   \(HotKey.display(store.settings.hotKey))", #selector(openLauncher))
        _ = add("Settings…", #selector(openSettings), key: ",")
        _ = add("Extension Studio…", #selector(openStudio))
        menu.addItem(.separator())
        _ = add("Pause Activation", #selector(togglePause), state: store.settings.activationPaused)
        _ = add("Mouse Gesture (hold both buttons, slide \(store.settings.gesture.slide))", #selector(toggleGesture),
                state: store.settings.gesture.enabled)
        if store.settings.gesture.enabled && !GestureMonitor.hasPermission {
            _ = add("    Grant Accessibility Access…", #selector(grantAccess))
        }

        let themeMenu = NSMenu()
        for id in store.themeIDs() {
            add(id, #selector(selectTheme(_:)), state: id == store.settings.theme, to: themeMenu).representedObject = id
        }
        add("Theme", nil).submenu = themeMenu

        let motionMenu = NSMenu()
        for (id, title) in [("system", "Follow System"), ("on", "On"), ("off", "Off")] {
            add(title, #selector(selectMotion(_:)), state: store.settings.reducedMotion == id, to: motionMenu).representedObject = id
        }
        add("Reduce Motion", nil).submenu = motionMenu
        _ = add("Sounds", #selector(toggleSounds), state: store.settings.soundsEnabled)
        _ = add("Show Widgets", #selector(toggleWidgets), state: store.settings.widgetsEnabled)
        _ = add("Edit Widgets…", #selector(editWidgets))

        menu.addItem(.separator())
        _ = add("Reload Configuration", #selector(reloadConfig), key: "r")
        _ = add("Show Configuration Folder", #selector(showConfig))
        _ = add("Show Log", #selector(showLog))

        let problems = store.problems + [hotKeyProblem, gestureProblem, notesProblem].compactMap { $0 } + itemShortcuts.problems
        if !problems.isEmpty {
            menu.addItem(.separator())
            for p in problems {
                let item = NSMenuItem(title: "⚠︎ " + p, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        _ = add("Quit AINCRAD", #selector(quit), key: "q")
    }

    @objc private func openLauncher() {
        // Let the status menu finish closing first, or its dismissal would resign our panel.
        DispatchQueue.main.async { self.launcher?.open() }
    }

    @objc private func openSettings() { showSettings() }
    @objc private func openStudio() { showStudio(nil) }

    @objc private func restartNormally() {
        guardian.end()
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }

    @objc private func togglePause() {
        store.update { $0.activationPaused.toggle() }
        applyActivation()
        Log.info("activation paused=\(store.settings.activationPaused)")
    }

    @objc private func toggleWidgets() {
        store.update { $0.widgetsEnabled.toggle() }
        widgets?.rebuildAll()
    }

    @objc private func editWidgets() {
        showSettings(tab: .widgets)
        widgets?.setEditing(true)
    }

    @objc private func toggleSounds() {
        store.update { $0.soundsEnabled.toggle() }
    }

    @objc private func toggleGesture() {
        store.update { $0.gesture.enabled.toggle() }
        if store.settings.gesture.enabled && !GestureMonitor.hasPermission { requestGesturePermission() }
        applyGesture()
        Log.info("gesture enabled=\(store.settings.gesture.enabled)")
    }

    @objc private func grantAccess() {
        requestGesturePermission()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.update { $0.theme = id }
        reload()
    }

    @objc private func selectMotion(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.update { $0.reducedMotion = id }
    }

    @objc private func reloadConfig() { reload() }
    @objc private func showConfig() { NSWorkspace.shared.activateFileViewerSelecting([store.menuURL]) }
    @objc private func showLog() { NSWorkspace.shared.open(Log.fileURL) }
    @objc private func quit() { NSApp.terminate(nil) }
}
