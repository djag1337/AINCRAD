import AppKit
import Combine

/// Owns widgets.json, one window per visible widget, and the edit/undo state shared with the
/// Widgets settings pane. A widget samples data only while its window is actually visible on
/// screen (not covered, display awake, widgets shown).
final class WidgetManager: NSObject, ObservableObject, WidgetHostDelegate {
    @Published var layout = WidgetLayout() { didSet { if layout != oldValue { sync() } } }
    @Published var selectedID: String? { didSet { if selectedID != oldValue { sync() } } }
    @Published private(set) var editing = false
    @Published private(set) var layoutNames: [String] = []

    var onOpenLauncher: ((CGRect) -> Void)?
    /// Widget presets contributed by enabled extensions, shown after the built-in library.
    var extraEntries: () -> [WidgetCatalog.Entry] = { [] }
    private let store: ConfigStore
    private var saved = WidgetLayout()
    private var undo = UndoStack<WidgetLayout>()
    private var hosts: [String: (panel: WidgetPanel, view: WidgetHostView, built: WidgetConfig)] = [:]
    private var running = Set<String>()
    private var displaysAsleep = false
    private var observers: [NSObjectProtocol] = []
    /// The display (widget `display` key) whose HUD is open, while the launcher is open there.
    private var hudDisplay: String?

    var url: URL { store.directory.appendingPathComponent("widgets.json") }
    var layoutsURL: URL { store.directory.appendingPathComponent("layouts", isDirectory: true) }
    var dirty: Bool { layout != saved }
    var canUndo: Bool { !undo.undos.isEmpty }
    var canRedo: Bool { !undo.redos.isEmpty }
    var selected: WidgetConfig? { layout.widgets.first { $0.id == selectedID } }

    init(store: ConfigStore) {
        self.store = store
        super.init()
        let ws = NSWorkspace.shared.notificationCenter
        observers = [
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.rebuildAll()
            },
            ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.displaysAsleep = true
                self?.updateRunning()
            },
            ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.displaysAsleep = false
                self?.updateRunning()
            },
        ]
    }

    // MARK: Persistence

    func load() {
        if let data = try? Data(contentsOf: url) {
            do {
                saved = try JSONDecoder().decode(WidgetLayout.self, from: data)
            } catch {
                Log.error("widgets.json: \(TolerantJSON.describe(error)) — widgets disabled until fixed")
                saved = WidgetLayout()
            }
        }
        layout = saved
        undo.clear()
        refreshLayoutNames()
        rebuildAll()
        Log.info("widgets loaded: \(layout.widgets.count)")
    }

    func save() {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let backup = store.backupsURL.appendingPathComponent("widgets-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.createDirectory(at: store.backupsURL, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: url, to: backup)
            }
            try TolerantJSON.encode(layout).write(to: url, options: .atomic)
            saved = layout
            objectWillChange.send()
        } catch {
            Log.error("widgets.json: could not save (\(error.localizedDescription))")
        }
    }

    func revert() {
        layout = saved
        undo.clear()
    }

    func refreshLayoutNames() {
        layoutNames = ((try? FileManager.default.contentsOfDirectory(atPath: layoutsURL.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    func saveLayout(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty else { return }
        try? FileManager.default.createDirectory(at: layoutsURL, withIntermediateDirectories: true)
        try? TolerantJSON.encode(layout).write(to: layoutsURL.appendingPathComponent(clean + ".json"), options: .atomic)
        refreshLayoutNames()
    }

    func loadLayout(named name: String) {
        guard let data = try? Data(contentsOf: layoutsURL.appendingPathComponent(name + ".json")),
              let l = try? JSONDecoder().decode(WidgetLayout.self, from: data) else { return }
        edit { $0 = l }
    }

    func deleteLayout(named name: String) {
        try? FileManager.default.removeItem(at: layoutsURL.appendingPathComponent(name + ".json"))
        refreshLayoutNames()
    }

    // MARK: Editing

    func edit(key: String? = nil, _ change: (inout WidgetLayout) -> Void) {
        var l = layout
        change(&l)
        guard l != layout else { return }
        undo.record(layout, key: key)
        layout = l
    }

    func update(_ id: String, key: String? = nil, _ change: (inout WidgetConfig) -> Void) {
        edit(key: key.map { "\(id).\($0)" }) { l in
            if let i = l.widgets.firstIndex(where: { $0.id == id }) { change(&l.widgets[i]) }
        }
    }

    func undoChange() { if let s = undo.undo(layout) { layout = s } }
    func redoChange() { if let s = undo.redo(layout) { layout = s } }

    /// Adds a widget near the middle of the display under the pointer (to the HUD layer with `hud`).
    func add(_ entry: WidgetCatalog.Entry, hud: Bool = false) {
        var w = entry.make()
        w.hud = hud
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let screen {
            w.display = screen == NSScreen.screens.first ? "" : screen.localizedName
            w.x = (screen.frame.width - w.width) / 2 + Double(layout.widgets.count % 5) * 24
            w.y = (screen.frame.height - w.height) / 2 + Double(layout.widgets.count % 5) * 24
        }
        w.z = (layout.widgets.map(\.z).max() ?? 0) + 1
        edit { $0.widgets.append(w) }
        selectedID = w.id
    }

    func remove(_ id: String) {
        edit { $0.widgets.removeAll { $0.id == id } }
        if selectedID == id { selectedID = nil }
    }

    func duplicate(_ id: String) {
        guard var w = layout.widgets.first(where: { $0.id == id }) else { return }
        w.id = UUID().uuidString
        w.x += 24
        w.y += 24
        w.z = (layout.widgets.map(\.z).max() ?? 0) + 1
        edit { $0.widgets.append(w) }
        selectedID = w.id
    }

    // MARK: HUD

    /// Shows the HUD widgets of `screen` above the launcher (nil hides them), sliding them in from
    /// the nearest screen edge.
    func setHUD(on screen: NSScreen?) {
        let key = screen.map(WidgetManager.displayKey)
        guard key != hudDisplay else { return }
        if let key {
            hudDisplay = key
            sync()
            dimDesktop(on: key, true)
            for (id, host) in hosts where host.built.hud && host.built.display == key {
                guard let w = layout.widgets.first(where: { $0.id == id }), let sc = screen else { continue }
                let fromLeft = w.x + w.width / 2 < Double(sc.frame.width) / 2
                host.view.animateIn(fromX: fromLeft ? -40 : 40)
            }
        } else {
            if let old = hudDisplay { dimDesktop(on: old, false) }
            let closing = hosts.filter { $0.value.built.hud && !editing }
            hudDisplay = nil
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.hudDisplay == nil else { return }
                self.sync()
            }
            closing.values.forEach { $0.view.animateOut() }
            CATransaction.commit()
        }
    }

    /// HUD widgets that a menu column overlaps fade back, so the menu stays readable on top.
    func avoid(_ rects: [CGRect]) {
        guard let display = hudDisplay, !editing else { return }
        for host in hosts.values where host.built.hud && host.built.display == display {
            let w = layout.widgets.first { $0.id == host.built.id } ?? host.built
            let covered = rects.contains { $0.intersects(host.panel.frame) }
            let target = covered ? opacity(w) * 0.15 : opacity(w)
            guard abs(host.panel.alphaValue - target) > 0.01 else { continue }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                host.panel.animator().alphaValue = target
            }
        }
    }

    /// Fades the desktop widgets of one display while its launcher is open, and back after.
    private func dimDesktop(on display: String, _ dim: Bool) {
        guard store.settings.dimDesktopWidgetsWithLauncher, !editing else { return }
        let targets = hosts.values.filter { !$0.built.hud && $0.built.display == display }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = dim ? 0.2 : 0.25
            for host in targets {
                let w = layout.widgets.first { $0.id == host.built.id } ?? host.built
                host.panel.animator().alphaValue = dim ? opacity(w) * 0.2 : opacity(w)
            }
        }
    }

    /// Adds the starter HUD widgets for every display, once; and the quest log, once, to HUDs set
    /// up before it existed. Asks for Calendar & Reminders access if a quest log needs it.
    func addHUDStarterIfNeeded() {
        defer {
            if layout.widgets.contains(where: { $0.type == "quests" }) && QuestStore.undecided { QuestStore.shared.requestAccess() }
        }
        if store.settings.hudStarterAdded && !store.settings.hudQuestLogAdded {
            store.update { $0.hudQuestLogAdded = true }
            let logs = NSScreen.screens.map { WidgetCatalog.hudQuestLog(display: WidgetManager.displayKey($0), size: $0.frame.size) }
            edit { $0.widgets += logs }
            save()
            Log.info("widgets: added the HUD quest log")
        }
        guard !store.settings.hudStarterAdded else { return }
        store.update { $0.hudQuestLogAdded = true }
        store.update { $0.hudStarterAdded = true }
        guard !layout.widgets.contains(where: \.hud) else { return }
        let starter = NSScreen.screens.flatMap { WidgetCatalog.hudStarter(display: WidgetManager.displayKey($0), size: $0.frame.size) }
        edit { $0.widgets += starter }
        save()
        Log.info("widgets: added \(starter.count) starter HUD widgets")
    }

    private func opacity(_ w: WidgetConfig) -> Double {
        w.hud ? w.opacity * min(max(store.settings.hudWidgetOpacity, 0.05), 1) : w.opacity
    }

    func setEditing(_ on: Bool) {
        editing = on
        rebuildAll()
    }

    // MARK: WidgetHostDelegate

    func widgetSelected(_ id: String) { selectedID = id }
    func widgetBeginChange(_ id: String) { undo.record(layout) }
    func widgetDelete(_ id: String) { remove(id) }
    func widgetOpenLauncher(at screenRect: CGRect) { onOpenLauncher?(screenRect) }

    /// Drag updates: no undo snapshot per frame (one was taken at mouse-down).
    func widgetLiveChange(_ id: String, _ change: (inout WidgetConfig) -> Void) {
        var l = layout
        if let i = l.widgets.firstIndex(where: { $0.id == id }) { change(&l.widgets[i]) }
        layout = l
    }

    // MARK: Windows

    /// Name used in the widgets' `display` field for a screen.
    static func displayKey(_ screen: NSScreen) -> String {
        screen == NSScreen.screens.first ? "" : screen.localizedName
    }

    static func screen(for display: String) -> NSScreen? {
        display.isEmpty ? NSScreen.screens.first : NSScreen.screens.first { $0.localizedName == display }
    }

    private var enabled: Bool { store.settings.widgetsEnabled }

    func rebuildAll() {
        hosts.keys.forEach(closeHost)
        sync()
    }

    /// Brings windows in line with `layout`: creates, rebuilds (content changed), moves, removes.
    private func sync() {
        // HUD widgets keep their windows between opens (building them took ~10 ms per open);
        // they're only ordered in while their display's HUD is open, or while editing.
        let wanted = enabled ? layout.widgets.filter { !$0.hidden && WidgetManager.screen(for: $0.display) != nil } : []
        let wantedIDs = Set(wanted.map(\.id))
        hosts.keys.filter { !wantedIDs.contains($0) }.forEach(closeHost)
        for w in wanted.sorted(by: { $0.z < $1.z }) {
            guard let screen = WidgetManager.screen(for: w.display) else { continue }
            if let host = hosts[w.id], !contentChanged(host.built, w) {
                place(host.panel, host.view, w, screen: screen)
            } else {
                closeHost(w.id)
                makeHost(w, screen: screen)
            }
            if w.hud, let host = hosts[w.id] {
                let shown = editing || w.display == hudDisplay
                if shown && !host.panel.isVisible { host.panel.orderFrontRegardless() }
                if !shown && host.panel.isVisible { host.panel.orderOut(nil) }
            }
        }
        updateRunning()
    }

    /// Size, type, style and props affect the layers; position, rotation, opacity, z and lock don't.
    private func contentChanged(_ a: WidgetConfig, _ b: WidgetConfig) -> Bool {
        a.type != b.type || a.width != b.width || a.height != b.height || a.style != b.style || a.props != b.props
            || a.display != b.display || a.hud != b.hud
    }

    private func accent(for w: WidgetConfig) -> NSColor {
        let key = w.display.isEmpty ? (NSScreen.screens.first?.localizedName ?? "") : w.display
        return themeColor(w.style.accent ?? store.settings.displayAccents[key] ?? store.theme.colors.accent)
    }

    private func makeHost(_ w: WidgetConfig, screen: NSScreen) {
        let panel = WidgetPanel()
        let view = WidgetHostView(config: w)
        view.delegate = self
        panel.contentView = view
        let content = WidgetFactory.make(w, theme: store.theme, accent: accent(for: w), scale: screen.backingScaleFactor)
        content.onLaunchMenu = { [weak self] rect in self?.onOpenLauncher?(rect) }
        view.install(content)
        hosts[w.id] = (panel, view, w)
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged(_:)),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        place(panel, view, w, screen: screen)
        panel.orderFrontRegardless()
    }

    private func place(_ panel: WidgetPanel, _ view: WidgetHostView, _ w: WidgetConfig, screen: NSScreen) {
        let m = editing ? WidgetHostView.editMargin : WidgetHostView.margin
        let a = w.rotation * .pi / 180
        let bw = abs(w.width * cos(a)) + abs(w.height * sin(a)), bh = abs(w.width * sin(a)) + abs(w.height * cos(a))
        let cx = screen.frame.minX + w.x + w.width / 2, cy = screen.frame.maxY - w.y - w.height / 2
        let frame = NSRect(x: cx - bw / 2 - m, y: cy - bh / 2 - m, width: bw + 2 * m, height: bh + 2 * m).integral
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        panel.alphaValue = opacity(w)
        // Over the launcher while the HUD is open; with the desktop widgets while editing.
        panel.level = w.hud && !editing ? NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.ignoresMouseEvents = !(editing || w.isInteractive)
        panel.allowsKey = editing
        view.apply(config: w, editing: editing, selected: editing && w.id == selectedID)
        if editing && w.id == selectedID { panel.orderFrontRegardless() }
    }

    private func closeHost(_ id: String) {
        guard let host = hosts.removeValue(forKey: id) else { return }
        host.view.widgetContent?.stop()
        running.remove(id)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: host.panel)
        host.panel.orderOut(nil)
    }

    @objc private func occlusionChanged(_ note: Notification) { updateRunning() }

    /// Starts data for visible widgets and stops it for covered ones.
    private func updateRunning() {
        let before = running
        defer {
            if running != before {
                Log.info("widgets sampling: \(running.count) of \(hosts.count) visible; data sources: \(DataHub.shared.activeSources.sorted())")
            }
        }
        for (id, host) in hosts {
            let visible = !displaysAsleep && host.panel.occlusionState.contains(.visible)
            if visible && !running.contains(id) {
                host.view.widgetContent?.start()
                running.insert(id)
            } else if !visible && running.contains(id) {
                host.view.widgetContent?.stop()
                running.remove(id)
            }
        }
    }

    var runningCount: Int { running.count }
}
