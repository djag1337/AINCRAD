import AppKit
import SwiftUI

/// Everything the Extension Studio edits, saved as an ordinary extension folder.
final class StudioModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case basics = "Basics", scripts = "Scripts", looks = "Looks", menus = "Menus", widgets = "Widgets", publish = "Publish"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .basics: return "info.circle"
            case .scripts: return "puzzlepiece.extension"
            case .looks: return "paintpalette"
            case .menus: return "list.bullet.indent"
            case .widgets: return "square.grid.2x2"
            case .publish: return "shippingbox"
            }
        }
    }

    struct BundledTheme: Identifiable, Equatable {
        var id = UUID().uuidString
        var file: String
        var theme: Theme
    }

    @Published var section: Section = .scripts
    @Published var name = "My Extension"
    @Published var extID = "user.my-extension"
    @Published var idEdited = false
    @Published var version = "1.0" { didSet { dirty = true } }
    @Published var author = NSFullUserName() { didSet { dirty = true } }
    @Published var summary = "" { didSet { dirty = true } }
    @Published var scripts: [Script] = [] { didSet { dirty = true } }
    @Published var themes: [BundledTheme] = [] { didSet { dirty = true } }
    @Published var menus: [ExtensionManifest.MenuDef] = [] { didSet { dirty = true } }
    @Published var widgets: [ExtensionManifest.WidgetDef] = [] { didSet { dirty = true } }
    @Published var log: [String] = []
    @Published var category: BlockCategory = .events
    @Published private(set) var dirty = false
    @Published var message: String?
    /// Folder this extension was opened from / saved to.
    @Published private(set) var folder: URL?

    let store: ConfigStore
    let extensions: ExtensionManager
    let runtime: ScriptRuntime
    var onSaved: () -> Void = {}
    private var undo = UndoStack<[Script]>()

    init(store: ConfigStore, extensions: ExtensionManager, runtime: ScriptRuntime) {
        self.store = store
        self.extensions = extensions
        self.runtime = runtime
        scripts = [Script(trigger: BlockSpec.spec("ext.started")!.make(),
                          steps: [{ var b = BlockSpec.spec("looks.message")!.make(); b.inputs["text"] = .literal("Hello from my extension!"); return b }()])]
        dirty = false
    }

    // MARK: Identity

    var permissions: [String] { ScriptEngine.requiredPermissions(scripts).sorted() }

    func setName(_ new: String) {
        name = new
        if !idEdited { extID = "user." + StudioModel.slug(new) }
        dirty = true
    }

    static func slug(_ s: String) -> String {
        let cleaned = String(s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
        let joined = cleaned.split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return joined.isEmpty ? "extension" : joined
    }

    var manifest: ExtensionManifest {
        ExtensionManifest(
            id: extID, name: name, version: version, apiVersion: ExtensionManifest.apiVersion,
            description: summary.isEmpty ? nil : summary, author: author.isEmpty ? nil : author,
            permissions: permissions,
            provides: .init(themes: themes.isEmpty ? nil : themes.map { "themes/\($0.file).json" },
                            menus: menus.isEmpty ? nil : menus,
                            dataSources: nil,
                            widgets: widgets.isEmpty ? nil : widgets,
                            scripts: scripts.isEmpty ? nil : scripts))
    }

    var problem: String? { ExtensionManager.validate(manifest) }

    /// Opens an existing extension folder for editing.
    func open(_ ext: LoadedExtension) {
        let m = ext.manifest
        name = m.name
        extID = m.id
        idEdited = true
        version = m.version
        author = m.author ?? ""
        summary = m.description ?? ""
        scripts = m.provides.scripts ?? []
        menus = m.provides.menus ?? []
        widgets = m.provides.widgets ?? []
        themes = (m.provides.themes ?? []).compactMap { rel in
            guard let url = ExtensionManager.contained(rel, in: ext.folder), let data = try? Data(contentsOf: url),
                  let t = try? TolerantJSON.decode(Theme.self, from: data, defaults: .classic) else { return nil }
            return BundledTheme(file: url.deletingPathExtension().lastPathComponent, theme: t)
        }
        folder = ext.folder
        undo.clear()
        dirty = false
    }

    // MARK: Script editing (with undo)

    var canUndo: Bool { !undo.undos.isEmpty }
    var canRedo: Bool { !undo.redos.isEmpty }

    func edit(key: String? = nil, _ change: (inout [Script]) -> Void) {
        var s = scripts
        change(&s)
        guard s != scripts else { return }
        undo.record(scripts, key: key)
        scripts = s
    }

    func undoEdit() { if let s = undo.undo(scripts) { scripts = s } }
    func redoEdit() { if let s = undo.redo(scripts) { scripts = s } }

    /// Applies a dropped block. Event blocks start new scripts; others go into `slot`.
    func drop(_ payload: BlockPayload, at slot: ScriptTree.Slot?) -> Bool {
        let block = payload.fromCanvas ? payload.block : payload.block.renewed()
        guard let spec = BlockSpec.spec(block.op) else { return false }
        if spec.kind == .hat {
            guard !payload.fromCanvas else { return false }
            edit { $0.append(Script(trigger: block)) }
            return true
        }
        guard !spec.isReporter, let slot else { return false }
        var ok = false
        edit { ok = ScriptTree.move(block, to: slot, in: &$0) }
        return ok
    }

    func dropReporter(_ payload: BlockPayload, into id: String, slot: String) -> Bool {
        let block = payload.fromCanvas ? payload.block : payload.block.renewed()
        guard BlockSpec.spec(block.op)?.isReporter == true else { return false }
        var ok = false
        edit { ok = ScriptTree.setInput(block, into: id, slot: slot, in: &$0) }
        return ok
    }

    func delete(_ id: String) {
        edit { s in
            if let i = s.firstIndex(where: { $0.trigger.id == id }) { s.remove(at: i) } else { ScriptTree.remove(id, from: &s) }
        }
    }

    func duplicate(_ id: String) {
        edit { s in
            if let i = s.firstIndex(where: { $0.trigger.id == id }) {
                var copy = s[i]
                copy.id = UUID().uuidString
                copy.trigger = copy.trigger.renewed()
                copy.steps = copy.steps.map { $0.renewed() }
                s.insert(copy, at: i + 1)
            } else if let b = s.flatMap(\.allBlocks).first(where: { $0.id == id }), !(BlockSpec.spec(b.op)?.isReporter ?? true) {
                ScriptTree.insert(b.renewed(), at: .after(id), in: &s)
            }
        }
    }

    func setLiteral(_ id: String, _ value: String) {
        edit(key: "lit." + id) { ScriptTree.mutate(id, in: &$0) { $0.fields["value"] = value } }
    }

    func setField(_ id: String, _ name: String, _ value: String) {
        edit(key: "field.\(id).\(name)") { ScriptTree.mutate(id, in: &$0) { $0.fields[name] = value } }
    }

    // MARK: Testing

    /// Runs one script now, against the saved folder (so its files are readable) or a temporary one.
    func test(_ script: Script) {
        log.append("▶ \(BlockSpec.spec(script.trigger.op)?.label ?? "script")")
        if let p = problem, p.contains("unknown") { log.append("⚠︎ \(p)"); return }
        let dir = folder ?? FileManager.default.temporaryDirectory.appendingPathComponent("aincrad-studio-test")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = LoadedExtension(manifest: manifest, folder: dir)
        runtime.test(script, ext: ext) { [weak self] line in
            DispatchQueue.main.async {
                self?.log.append(line)
                if (self?.log.count ?? 0) > 300 { self?.log.removeFirst(100) }
            }
        }
    }

    // MARK: Saving

    /// Writes the extension into AINCRAD's Extensions folder (replacing an earlier save) and reloads.
    @discardableResult
    func save() -> LoadedExtension? {
        if let p = problem { message = "Can't save yet: \(p)"; return nil }
        let dir = extensions.folder.appendingPathComponent(extID, isDirectory: true)
        do {
            try write(to: dir)
            folder = dir
            dirty = false
            extensions.load()
            onSaved()
            Log.info("studio saved \(extID)")
            return extensions.extensions.first { $0.id == extID }
        } catch {
            message = "Save failed: \(error.localizedDescription)"
            return nil
        }
    }

    func write(to dir: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("themes"), withIntermediateDirectories: true)
        // Keep data files the user put in the folder; replace only what the Studio owns.
        let themeDir = dir.appendingPathComponent("themes")
        for old in (try? fm.contentsOfDirectory(at: themeDir, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: old) }
        for t in themes { try ConfigStore.themeData(t.theme).write(to: themeDir.appendingPathComponent(t.file + ".json"), options: .atomic) }
        try TolerantJSON.encode(manifest).write(to: dir.appendingPathComponent("extension.json"), options: .atomic)
    }

    /// Saves, then zips the folder into a shareable .aincrad file.
    func export() {
        guard let ext = save() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = StudioModel.slug(name) + ".aincrad"
        panel.allowedContentTypes = [.aincradPackage]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Packages.zip(ext.folder, to: url)
            message = "Exported \(url.lastPathComponent). Double-clicking it installs the extension in AINCRAD."
        } catch { message = "Export failed: \(error.localizedDescription)" }
    }

    @Published var publishing = false

    /// Saves, then publishes into the catalog repo (copy, build, commit, push) in the background.
    func publish() {
        guard let ext = save() else { return }
        publishing = true
        let repo = Publisher.repoURL(store.settings.catalogRepoPath)
        let item = Publisher.Item.extensionFolder(ext.folder, id: ext.id, name: name, version: version)
        log.append("⇪ publishing \(name) \(version) to \(repo.path)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let say: (String) -> Void = { line in
                guard !line.isEmpty else { return }
                DispatchQueue.main.async { self?.log.append(line) }
            }
            do {
                let page = try Publisher.publish(item, repo: repo, log: say)
                DispatchQueue.main.async {
                    self?.publishing = false
                    self?.message = "Published! It's in the catalog at \(page) — Browse will show it within a few minutes (GitHub caches raw files briefly)."
                }
            } catch {
                DispatchQueue.main.async {
                    self?.publishing = false
                    self?.log.append("✗ \(error.localizedDescription)")
                    self?.message = "Publish failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: Looks, menus, widgets

    func addTheme(from id: String) {
        var t = store.loadTheme(id)
        t.name = t.name + " (\(name))"
        themes.append(BundledTheme(file: StudioModel.slug(id) + "-\(themes.count + 1)", theme: t))
    }

    var gaugeSources: [(key: String, title: String)] {
        ScriptTree.gaugeNames(scripts).map { ("script:\(extID)/\($0)", "Gauge: \($0)") }
    }
}

/// What a dragged block carries: the block, and whether it was already on the canvas (a move)
/// or comes from the palette (a copy).
struct BlockPayload: Codable {
    static let prefix = "AINCRAD-BLOCK:"
    var block: Block
    var fromCanvas: Bool

    var string: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }.map { BlockPayload.prefix + $0 } ?? ""
    }

    static func decode(_ s: String) -> BlockPayload? {
        guard s.hasPrefix(prefix) else { return nil }
        return try? JSONDecoder().decode(BlockPayload.self, from: Data(s.dropFirst(prefix.count).utf8))
    }
}
