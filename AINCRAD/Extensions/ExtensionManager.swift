import AppKit

/// Extension API v1. An extension is a folder with an `extension.json` manifest that can
/// contribute themes, menus, data sources and widget presets. Extensions are declarative:
/// they never run code inside AINCRAD. Anything reaching outside the extension's own folder
/// (network, other files) is a named permission the user approves per extension.
struct ExtensionManifest: Codable, Equatable {
    static let apiVersion = 1

    var id: String
    var name: String
    var version: String
    var apiVersion: Int
    var description: String?
    var author: String?
    /// "network": data sources may fetch http(s) URLs. "files": data sources may read files outside the extension folder.
    var permissions: [String]?
    var provides: Provides

    struct Provides: Codable, Equatable {
        /// Theme files, relative to the extension folder.
        var themes: [String]?
        /// Menus usable as a dynamic list: provider "ext:<extension id>/<menu id>".
        var menus: [MenuDef]?
        /// Readings usable by stat widgets: source "ext:<extension id>/<source id>".
        var dataSources: [DataSourceDef]?
        /// Widget presets that appear in the Widgets library.
        var widgets: [WidgetDef]?
        /// Block scripts (made in the Extension Studio), run by AINCRAD's interpreter.
        var scripts: [Script]?
    }

    struct MenuDef: Codable, Equatable { var id: String; var name: String; var items: [MenuItem] }

    struct DataSourceDef: Codable, Equatable {
        var id: String
        var name: String
        /// One of `url` (needs "network") or `file` (inside the extension folder, or anywhere with "files").
        var url: String?
        var file: String?
        /// Seconds; network sources are clamped to at least 60.
        var interval: Double?
        /// Dot path into the JSON, e.g. "current.temperature" or "items.0.value". Empty = the whole document.
        var value: String?
        /// Readout template; "{value}" is replaced. Default: the value itself.
        var text: String?
        /// When set, the bar fill is value / max.
        var max: Double?
    }

    struct WidgetDef: Codable, Equatable { var name: String; var widget: WidgetConfig }
}

struct LoadedExtension: Identifiable {
    let manifest: ExtensionManifest
    let folder: URL
    var id: String { manifest.id }
    var requested: Set<String> { Set(manifest.permissions ?? []) }
}

final class ExtensionManager: ObservableObject {
    @Published private(set) var extensions: [LoadedExtension] = []
    @Published private(set) var problems: [String] = []
    private let store: ConfigStore

    var folder: URL { store.directory.appendingPathComponent("Extensions", isDirectory: true) }

    init(store: ConfigStore) { self.store = store }

    func isEnabled(_ ext: LoadedExtension) -> Bool {
        guard let a = store.settings.extensions[ext.id], a.enabled else { return false }
        return ext.requested.isSubset(of: Set(a.permissions))
    }

    /// Copies the plugins bundled with AINCRAD into Extensions/, switched off like any new
    /// extension. One the user deleted stays deleted; a newer bundled version replaces an older copy.
    func seedBundledPlugins() {
        guard let bundled = Bundle.main.url(forResource: "Plugins", withExtension: nil) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var seeded = store.settings.seededPlugins
        for dir in ((try? fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.path < $1.path }) {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("extension.json")),
                  let m = try? JSONDecoder().decode(ExtensionManifest.self, from: data) else { continue }
            let dest = folder.appendingPathComponent(dir.lastPathComponent)
            let exists = fm.fileExists(atPath: dest.path)
            if let had = seeded[m.id] {
                guard exists, had.compare(m.version, options: .numeric) == .orderedAscending else { continue }
                try? fm.removeItem(at: dest)
            } else if exists {
                // Already installed (e.g. from the catalog): leave the user's copy alone.
                seeded[m.id] = m.version
                continue
            }
            do {
                try fm.copyItem(at: dir, to: dest)
                seeded[m.id] = m.version
                Log.info("plugins: installed \(m.id) \(m.version)")
            } catch {
                Log.error("plugins: couldn't install \(m.id): \(error.localizedDescription)")
            }
        }
        if seeded != store.settings.seededPlugins { store.update { $0.seededPlugins = seeded } }
    }

    func load() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var found: [LoadedExtension] = [], errors: [String] = []
        let dirs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for dir in dirs.sorted(by: { $0.path < $1.path }) {
            let manifestURL = dir.appendingPathComponent("extension.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let m = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: manifestURL))
                if let problem = ExtensionManager.validate(m) {
                    errors.append("\(dir.lastPathComponent): \(problem)")
                } else if found.contains(where: { $0.id == m.id }) {
                    errors.append("\(dir.lastPathComponent): duplicate id \(m.id)")
                } else {
                    found.append(LoadedExtension(manifest: m, folder: dir))
                }
            } catch {
                errors.append("\(dir.lastPathComponent)/extension.json: \(TolerantJSON.describe(error))")
            }
        }
        extensions = found
        problems = errors
        errors.forEach { Log.error("extension \($0)") }
        registerSources()
        Log.info("extensions: \(found.count) found, \(found.filter(isEnabled).count) enabled")
    }

    static func validate(_ m: ExtensionManifest) -> String? {
        if m.apiVersion > ExtensionManifest.apiVersion { return "needs API version \(m.apiVersion); this AINCRAD supports \(ExtensionManifest.apiVersion)" }
        if m.id.isEmpty || m.id.contains(where: { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) {
            return "id must use only letters, numbers, dots and dashes"
        }
        let unknown = Set(m.permissions ?? []).subtracting(["network", "files"])
        if !unknown.isEmpty { return "unknown permissions: \(unknown.sorted().joined(separator: ", "))" }
        let needed = ScriptEngine.requiredPermissions(m.provides.scripts ?? [])
        let missing = needed.subtracting(m.permissions ?? [])
        if !missing.isEmpty { return "scripts use blocks needing \(missing.sorted().joined(separator: ", ")), which the manifest doesn't request" }
        let unknownBlocks = Set((m.provides.scripts ?? []).flatMap(\.allBlocks).map(\.op)).filter { $0 != "literal" && BlockSpec.spec($0) == nil }
        if !unknownBlocks.isEmpty { return "unknown blocks: \(unknownBlocks.sorted().joined(separator: ", ")) (made for a newer AINCRAD?)" }
        for s in m.provides.dataSources ?? [] {
            if (s.url == nil) == (s.file == nil) { return "data source \(s.id) needs exactly one of url or file" }
            if s.url != nil && !(m.permissions ?? []).contains("network") { return "data source \(s.id) uses a URL but doesn't request \"network\"" }
            if let u = s.url, let scheme = URL(string: u)?.scheme?.lowercased(), !["http", "https"].contains(scheme) {
                return "data source \(s.id): only http(s) URLs are allowed"
            }
        }
        return nil
    }

    func setEnabled(_ ext: LoadedExtension, _ on: Bool) {
        store.update { $0.extensions[ext.id] = ExtensionApproval(enabled: on, permissions: on ? ext.requested.sorted() : []) }
        registerSources()
        objectWillChange.send()
        Log.info("extension \(ext.id) enabled=\(on)")
    }

    // MARK: Contributions

    func menuItems(_ provider: String) -> [MenuItem]? {
        guard provider.hasPrefix("ext:") else { return nil }
        // Every enabled extension's menus, for Command Center › Extensions.
        if provider == "ext:all" {
            let menus = extensions.filter(isEnabled).flatMap { ext in
                (ext.manifest.provides.menus ?? []).map {
                    MenuItem(id: "ext:\(ext.id)/\($0.id)", name: $0.name, icon: "sf:puzzlepiece.extension.fill", children: $0.items)
                }
            }
            return menus.isEmpty
                ? [MenuItem(id: "ext:none", name: "Turn extensions on in Settings › Extensions", icon: "sf:puzzlepiece.extension", action: .builtin("settings"))]
                : menus
        }
        let parts = provider.dropFirst(4).split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let ext = extensions.first(where: { $0.id == parts[0] }), isEnabled(ext) else { return [] }
        return ext.manifest.provides.menus?.first { $0.id == parts[1] }?.items ?? []
    }

    var menuProviders: [(id: String, name: String)] {
        extensions.filter(isEnabled).flatMap { ext in
            (ext.manifest.provides.menus ?? []).map { ("ext:\(ext.id)/\($0.id)", "\(ext.manifest.name): \($0.name)") }
        }
    }

    var widgetPresets: [WidgetCatalog.Entry] {
        extensions.filter(isEnabled).flatMap { ext in
            (ext.manifest.provides.widgets ?? []).map { def in
                WidgetCatalog.Entry(type: def.widget.type, name: def.name, symbol: "puzzlepiece.extension") {
                    var w = def.widget
                    w.id = UUID().uuidString
                    return w
                }
            }
        }
    }

    /// Copies an extension's themes into themes/ (validated), named "<extension id>-<file>".
    func installThemes(_ ext: LoadedExtension) throws -> [String] {
        try (ext.manifest.provides.themes ?? []).map { rel in
            guard let url = contained(rel, in: ext.folder) else { throw ConfigStore.StoreError.invalid("\(rel) is outside the extension folder") }
            let data = try Data(contentsOf: url)
            let theme = try TolerantJSON.decode(Theme.self, from: data, defaults: .classic)
            let id = store.freeThemeID(ext.id + "-" + url.deletingPathExtension().lastPathComponent)
            try store.saveTheme(theme, id: id)
            return id
        }
    }

    private func registerSources() {
        DataHub.shared.unregisterAll(prefix: "ext:")
        for ext in extensions where isEnabled(ext) {
            for def in ext.manifest.provides.dataSources ?? [] {
                let key = "ext:\(ext.id)/\(def.id)"
                let interval = max(def.url != nil ? 60 : 5, def.interval ?? 300)
                let fileAllowed = ext.requested.contains("files")
                let folder = ext.folder
                DataHub.shared.register(key, DataHub.ExternalSource(title: def.name, interval: interval) { done in
                    ExtensionManager.fetch(def, folder: folder, filesAllowed: fileAllowed, done: done)
                })
            }
        }
    }

    static func fetch(_ def: ExtensionManifest.DataSourceDef, folder: URL, filesAllowed: Bool,
                      done: @escaping (StatSample?) -> Void) {
        func finish(_ data: Data?) { done(data.flatMap { sample(from: $0, def: def) }) }
        if let u = def.url, let url = URL(string: u) {
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            req.setValue("AINCRAD", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, _, error in
                if let error { Log.error("extension source \(def.id): \(error.localizedDescription)") }
                finish(data)
            }.resume()
        } else if let f = def.file {
            let url = filesAllowed && (f.hasPrefix("/") || f.hasPrefix("~"))
                ? URL(fileURLWithPath: (f as NSString).expandingTildeInPath)
                : contained(f, in: folder)
            DispatchQueue.global(qos: .utility).async { finish(url.flatMap { try? Data(contentsOf: $0) }) }
        } else {
            done(nil)
        }
    }

    /// Reads `value` (a dot path) out of JSON, or treats a non-JSON file as plain text.
    static func sample(from data: Data, def: ExtensionManifest.DataSourceDef) -> StatSample? {
        var node: Any? = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
            ?? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        for part in (def.value ?? "").split(separator: ".") {
            if let i = Int(part), let a = node as? [Any] { node = a.indices.contains(i) ? a[i] : nil }
            else { node = (node as? [String: Any])?[String(part)] }
        }
        guard let node else { return nil }
        let number = (node as? NSNumber)?.doubleValue ?? Double("\(node)")
        let shown = number.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.1f", $0) } ?? "\(node)"
        let text = (def.text ?? "{value}").replacingOccurrences(of: "{value}", with: shown)
        var fraction: Double?
        if let n = number, let m = def.max, m > 0 { fraction = min(max(n / m, 0), 1) }
        return StatSample(fraction: fraction, text: text, used: number, total: def.max)
    }

    /// Resolves a relative path, refusing anything that escapes the folder.
    static func contained(_ relative: String, in folder: URL) -> URL? {
        let url = folder.appendingPathComponent(relative).standardizedFileURL
        return url.path.hasPrefix(folder.standardizedFileURL.path + "/") ? url : nil
    }

    private func contained(_ relative: String, in folder: URL) -> URL? { ExtensionManager.contained(relative, in: folder) }

    /// Writes a small example extension that exercises every contribution type without network access.
    func createExample() throws -> URL {
        let dir = folder.appendingPathComponent("aincrad-example", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("themes"), withIntermediateDirectories: true)
        let manifest = ExtensionManifest(
            id: "aincrad.example", name: "AINCRAD Example", version: "1.0", apiVersion: 1,
            description: "Shows what an extension can provide: a theme, a menu, a data source and a widget preset.",
            author: "AINCRAD", permissions: [],
            provides: .init(
                themes: ["themes/alfheim.json"],
                menus: [.init(id: "links", name: "Example Links", items: [
                    MenuItem(id: "ex-1", name: "Swift Documentation", icon: "sf:swift", action: .url("https://www.swift.org/documentation/")),
                    MenuItem(id: "ex-2", name: "Extensions Folder", icon: "sf:folder.fill", action: .open(folder.path)),
                ])],
                dataSources: [.init(id: "floor", name: "Floor", file: "progress.json", interval: 30, value: "floor", text: "Floor {value} / 100", max: 100)],
                widgets: [.init(name: "Aincrad floor progress", widget: WidgetConfig(
                    type: "stat", width: 260, height: 70, props: ["source": "ext:aincrad.example/floor", "show": "bar", "label": "Aincrad"]))]))
        try TolerantJSON.encode(manifest).write(to: dir.appendingPathComponent("extension.json"), options: .atomic)
        try Data(#"{"floor": 75}"#.utf8).write(to: dir.appendingPathComponent("progress.json"), options: .atomic)
        var alfheim = Theme.classic
        alfheim.name = "Alfheim (example)"
        alfheim.colors.accent = "#5FD068"
        try ConfigStore.themeData(alfheim).write(to: dir.appendingPathComponent("themes/alfheim.json"), options: .atomic)
        load()
        return dir
    }
}

struct ExtensionApproval: Codable, Equatable {
    var enabled = false
    /// The permissions the user approved; enabling again is required if an update asks for more.
    var permissions: [String] = []
}
