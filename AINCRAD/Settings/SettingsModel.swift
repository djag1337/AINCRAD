import AppKit
import SwiftUI

/// What the settings window may ask of the running app.
struct AppActions {
    var applySettings: () -> Void
    var reloadAll: () -> Void
    var previewMenu: (MenuFile, Theme?) -> Void
    var suspendHotKeys: (Bool) -> Void
    var requestAccessibility: () -> Void
    var hasAccessibility: () -> Bool
    var openStudio: (LoadedExtension?) -> Void = { _ in }
    var installPackage: (URL) -> Void = { _ in }
    var testBubble: () -> Void = {}
}

/// Snapshot undo with coalescing, so typing a name is one undo step, not one per letter.
struct UndoStack<T> {
    private(set) var undos: [T] = []
    private(set) var redos: [T] = []
    private var lastKey = ""
    private var lastTime = Date.distantPast

    mutating func record(_ state: T, key: String? = nil) {
        if let key, key == lastKey, Date().timeIntervalSince(lastTime) < 1.2 { lastTime = Date(); return }
        undos.append(state)
        if undos.count > 200 { undos.removeFirst() }
        redos = []
        lastKey = key ?? ""
        lastTime = Date()
    }

    mutating func undo(_ current: T) -> T? {
        guard let s = undos.popLast() else { return nil }
        redos.append(current)
        lastKey = ""
        return s
    }

    mutating func redo(_ current: T) -> T? {
        guard let s = redos.popLast() else { return nil }
        undos.append(current)
        lastKey = ""
        return s
    }

    mutating func clear() { undos = []; redos = []; lastKey = "" }
}

final class SettingsModel: ObservableObject {
    let store: ConfigStore
    let actions: AppActions
    let widgets: WidgetManager
    let extensions: ExtensionManager
    let catalog: CatalogModel

    @Published var settings: AppSettings
    @Published var tab: SettingsView.Tab = .general
    @Published var message: String?

    // Menu editor
    @Published var menu: MenuFile
    @Published var selectedItemID: String?
    /// Unsaved = differs from what's on disk, so undoing back to the saved state clears it.
    var menuDirty: Bool { menu != store.menu }
    private var menuUndo = UndoStack<MenuFile>()

    // Theme editor
    @Published var themeIDs: [String] = []
    @Published private(set) var editingThemeID = ""
    @Published var theme = Theme.classic
    private var savedTheme = Theme.classic
    var themeDirty: Bool { theme != savedTheme }
    private var themeUndo = UndoStack<Theme>()

    init(store: ConfigStore, actions: AppActions, widgets: WidgetManager, extensions: ExtensionManager) {
        self.store = store
        self.actions = actions
        self.widgets = widgets
        self.extensions = extensions
        catalog = MainActor.assumeIsolated { CatalogModel(store: store, extensions: extensions) }
        settings = store.settings
        menu = store.menu
        refreshThemes()
        selectTheme(store.settings.theme)
    }

    // MARK: General

    func update(_ change: (inout AppSettings) -> Void) {
        store.update(change)
        settings = store.settings
        actions.applySettings()
    }

    // MARK: Menu

    var canUndoMenu: Bool { !menuUndo.undos.isEmpty }
    var canRedoMenu: Bool { !menuUndo.redos.isEmpty }

    var selectedItem: MenuItem? { selectedItemID.flatMap { MenuTree.find($0, in: menu.root) } }

    /// Applies a structural or field edit with an undo snapshot. `key` merges rapid edits of one field.
    func editMenu(key: String? = nil, _ change: (inout [MenuItem]) -> Void) {
        let before = menu
        var root = menu.root
        change(&root)
        guard root != before.root else { return }
        menuUndo.record(before, key: key)
        menu.root = root
    }

    func updateSelected(_ item: MenuItem, field: String) {
        editMenu(key: "\(item.id).\(field)") { MenuTree.replace(item, in: &$0) }
    }

    func addItem(submenu: Bool) {
        let new = submenu
            ? MenuItem(name: "New Menu", icon: "sf:folder.fill", children: [])
            : MenuItem(name: "New Item", action: .url("https://"))
        editMenu { root in
            if let sel = selectedItem, sel.children != nil, sel.provider == nil {
                MenuTree.insert(new, inside: sel.id, in: &root)
            } else {
                MenuTree.insert(new, after: selectedItemID, in: &root)
            }
        }
        selectedItemID = new.id
    }

    func deleteSelected() {
        guard let id = selectedItemID else { return }
        let ids = MenuTree.allIDs(menu.root)
        let next = ids.firstIndex(of: id).flatMap { i in i + 1 < ids.count ? ids[i + 1] : (i > 0 ? ids[i - 1] : nil) }
        editMenu { _ = MenuTree.remove(id, in: &$0) }
        selectedItemID = next.flatMap { MenuTree.find($0, in: menu.root) != nil ? $0 : nil }
    }

    func duplicateSelected() {
        guard let id = selectedItemID else { return }
        var newID: String?
        editMenu { newID = MenuTree.duplicate(id, in: &$0) }
        selectedItemID = newID
    }

    func moveSelected(_ delta: Int) { if let id = selectedItemID { editMenu { _ = MenuTree.move(id, by: delta, in: &$0) } } }
    func indentSelected() { if let id = selectedItemID { editMenu { _ = MenuTree.indent(id, in: &$0) } } }
    func outdentSelected() { if let id = selectedItemID { editMenu { _ = MenuTree.outdent(id, in: &$0) } } }

    func undoMenu() { if let s = menuUndo.undo(menu) { menu = s; keepSelection() } }
    func redoMenu() { if let s = menuUndo.redo(menu) { menu = s; keepSelection() } }

    private func keepSelection() {
        if let id = selectedItemID, MenuTree.find(id, in: menu.root) == nil { selectedItemID = nil }
    }

    func saveMenu() {
        do {
            try store.saveMenu(menu)
            actions.reloadAll()
            message = "Menu saved. The previous version is in backups/."
        } catch { message = "Could not save the menu: \(error.localizedDescription)" }
    }

    func revertMenu() {
        menu = store.menu
        menuUndo.clear()
        keepSelection()
    }

    func previewMenu() { actions.previewMenu(menu, nil) }

    func importMenu() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try store.importMenu(from: url)
            editMenu { $0 = imported.root }
            message = "Imported \(url.lastPathComponent). Review it, then Save."
        } catch { message = error.localizedDescription }
    }

    func exportMenu() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "aincrad-menu.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try TolerantJSON.encode(menu).write(to: url, options: .atomic) }
        catch { message = "Export failed: \(error.localizedDescription)" }
    }

    // MARK: Themes

    var canUndoTheme: Bool { !themeUndo.undos.isEmpty }
    var canRedoTheme: Bool { !themeUndo.redos.isEmpty }

    func refreshThemes() { themeIDs = store.themeIDs() }

    func selectTheme(_ id: String) {
        editingThemeID = id
        theme = store.loadTheme(id)
        savedTheme = theme
        themeUndo.clear()
    }

    func editTheme(key: String? = nil, _ change: (inout Theme) -> Void) {
        let before = theme
        var t = theme
        change(&t)
        guard t != before else { return }
        themeUndo.record(before, key: key)
        theme = t
    }

    /// Binding into the edited theme that records undo per field.
    func themeBinding<V: Equatable>(_ path: WritableKeyPath<Theme, V>, key: String) -> Binding<V> {
        Binding(get: { self.theme[keyPath: path] },
                set: { v in self.editTheme(key: key) { $0[keyPath: path] = v } })
    }

    func undoTheme() { if let s = themeUndo.undo(theme) { theme = s } }
    func redoTheme() { if let s = themeUndo.redo(theme) { theme = s } }

    func saveTheme() {
        do {
            try store.saveTheme(theme, id: editingThemeID)
            savedTheme = theme
            actions.reloadAll()
        } catch { message = "Could not save the theme: \(error.localizedDescription)" }
    }

    func revertTheme() { selectTheme(editingThemeID) }

    func useTheme(_ id: String) {
        update { $0.theme = id }
        actions.reloadAll()
    }

    func previewTheme() { actions.previewMenu(store.menu, theme) }

    @Published var publishingTheme = false

    /// Publishes the edited theme into the catalog repo (copy, build, commit, push).
    func publishTheme() {
        if themeDirty { saveTheme() }
        let repo = Publisher.repoURL(settings.catalogRepoPath)
        let theme = self.theme, id = editingThemeID
        publishingTheme = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let page = try Publisher.publish(.theme(theme, id: id), repo: repo) { Log.info("publish: \($0)") }
                DispatchQueue.main.async {
                    self?.publishingTheme = false
                    self?.message = "Published “\(theme.name)” to \(page)."
                }
            } catch {
                DispatchQueue.main.async {
                    self?.publishingTheme = false
                    self?.message = "Publish failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func duplicateTheme() {
        do {
            let id = try store.duplicateTheme(editingThemeID)
            refreshThemes()
            selectTheme(id)
        } catch { message = error.localizedDescription }
    }

    func deleteTheme() {
        do {
            try store.deleteTheme(editingThemeID)
            refreshThemes()
            selectTheme(settings.theme)
        } catch { message = error.localizedDescription }
    }

    func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let id = try store.importTheme(from: url)
            refreshThemes()
            selectTheme(id)
            message = "Imported theme \"\(theme.name)\"."
        } catch { message = error.localizedDescription }
    }

    func exportTheme() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = editingThemeID + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if themeDirty { saveTheme() }
        do { try store.exportTheme(editingThemeID, to: url) }
        catch { message = "Export failed: \(error.localizedDescription)" }
    }
}

extension MenuItem: Identifiable {}

extension NSColor {
    /// "#RRGGBB", or "#RRGGBBAA" when not fully opaque.
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded()), a = Int((c.alphaComponent * 255).rounded())
        return a == 255 ? String(format: "#%02X%02X%02X", r, g, b) : String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

/// Color ↔ hex-string binding for theme and item colours.
func hexColor(_ binding: Binding<String>) -> Binding<Color> {
    Binding(get: { Color(nsColor: NSColor(hex: binding.wrappedValue) ?? .magenta) },
            set: { binding.wrappedValue = NSColor($0).hexString })
}
