import Foundation

/// Owns the JSON files in ~/Library/Application Support/AINCRAD. Never overwrites a file the user broke.
final class ConfigStore {
    static let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AINCRAD", isDirectory: true)

    let directory: URL
    var settingsURL: URL { directory.appendingPathComponent("settings.json") }
    var menuURL: URL { directory.appendingPathComponent("menu.json") }
    var themesURL: URL { directory.appendingPathComponent("themes", isDirectory: true) }

    private(set) var settings = AppSettings() {
        didSet { if settings.theme != oldValue.theme || settings.playerName != oldValue.playerName { BrowserLink.announceTheme() } }
    }
    private(set) var theme = Theme.classic {
        didSet { if theme != oldValue { BrowserLink.announceTheme() } }
    }
    private(set) var menu = MenuFile(root: [])
    private(set) var problems: [String] = []

    init(directory: URL = ConfigStore.baseDirectory) {
        self.directory = directory
    }

    func load() {
        problems = []
        try? FileManager.default.createDirectory(at: themesURL, withIntermediateDirectories: true)
        writeIfMissing(settingsURL) { AppSettings() }
        writeIfMissing(menuURL) { DefaultMenu.build() }
        for preset in Theme.presets {
            let url = themesURL.appendingPathComponent(preset.id + ".json")
            if !FileManager.default.fileExists(atPath: url.path) {
                do { try ConfigStore.themeData(preset.theme).write(to: url, options: .atomic) }
                catch { report("\(url.lastPathComponent): could not create (\(error.localizedDescription))") }
            }
        }

        settings = read(settingsURL, defaults: AppSettings())
        theme = readTheme(themesURL.appendingPathComponent(settings.theme + ".json"))
        do {
            menu = try JSONDecoder().decode(MenuFile.self, from: Data(contentsOf: menuURL))
        } catch {
            report("menu.json: \(TolerantJSON.describe(error)) — using the built-in menu")
            menu = DefaultMenu.build()
        }
        Log.info("config loaded: theme=\(settings.theme) rootItems=\(menu.root.count) problems=\(problems.count)")
    }

    func update(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        do { try TolerantJSON.encode(settings).write(to: settingsURL, options: .atomic) }
        catch { report("settings.json: could not save (\(error.localizedDescription))") }
    }

    var backupsURL: URL { directory.appendingPathComponent("backups", isDirectory: true) }

    enum StoreError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let m) = self { return m }; return nil }
    }

    /// Saves the menu after copying the current file into backups/ (the newest 15 are kept).
    func saveMenu(_ menu: MenuFile) throws {
        backup(menuURL)
        try TolerantJSON.encode(menu).write(to: menuURL, options: .atomic)
        self.menu = menu
        Log.info("menu saved (\(MenuTree.allIDs(menu.root).count) items)")
    }

    func themeIDs() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: themesURL.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    func themeURL(_ id: String) -> URL { themesURL.appendingPathComponent(id + ".json") }

    func loadTheme(_ id: String) -> Theme { readTheme(themeURL(id)) }

    func saveTheme(_ theme: Theme, id: String) throws {
        backup(themeURL(id))
        try ConfigStore.themeData(theme).write(to: themeURL(id), options: .atomic)
        if id == settings.theme { self.theme = theme }
        Log.info("theme \(id) saved")
    }

    /// A file-name-safe id that isn't taken yet, derived from `name`.
    func freeThemeID(_ name: String) -> String {
        let base = String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
            .split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        let root = base.isEmpty ? "theme" : base
        var id = root, n = 2
        while FileManager.default.fileExists(atPath: themeURL(id).path) { id = "\(root)-\(n)"; n += 1 }
        return id
    }

    func duplicateTheme(_ id: String) throws -> String {
        var t = loadTheme(id)
        t.name += " Copy"
        let new = freeThemeID(t.name)
        try saveTheme(t, id: new)
        return new
    }

    /// Validates by decoding before copying, so a bad file never lands in themes/.
    func importTheme(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let theme: Theme
        do { theme = try TolerantJSON.decode(Theme.self, from: data, defaults: .classic) }
        catch { throw StoreError.invalid("Not a valid AINCRAD theme: \(TolerantJSON.describe(error))") }
        let id = freeThemeID(url.deletingPathExtension().lastPathComponent)
        try ConfigStore.themeData(theme).write(to: themeURL(id), options: .atomic)
        Log.info("theme imported as \(id)")
        return id
    }

    func exportTheme(_ id: String, to url: URL) throws {
        try ConfigStore.themeData(loadTheme(id)).write(to: url, options: .atomic)
    }

    func deleteTheme(_ id: String) throws {
        guard id != settings.theme else { throw StoreError.invalid("The active theme can't be deleted; choose another first.") }
        backup(themeURL(id))
        try FileManager.default.removeItem(at: themeURL(id))
    }

    func importMenu(from url: URL) throws -> MenuFile {
        do { return try JSONDecoder().decode(MenuFile.self, from: Data(contentsOf: url)) }
        catch { throw StoreError.invalid("Not a valid AINCRAD menu: \(TolerantJSON.describe(error))") }
    }

    private func backup(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let name = url.deletingPathExtension().lastPathComponent
        try? fm.copyItem(at: url, to: backupsURL.appendingPathComponent("\(name)-\(stamp).json"))
        let old = ((try? fm.contentsOfDirectory(atPath: backupsURL.path)) ?? [])
            .filter { $0.hasPrefix(name + "-") && $0.hasSuffix(".json") }.sorted()
        old.dropLast(15).forEach { try? fm.removeItem(at: backupsURL.appendingPathComponent($0)) }
    }

    /// Theme JSON for writing; animation values that just repeat the preset are left out so
    /// changing "preset" in the file actually changes the motion.
    static func themeData(_ theme: Theme) throws -> Data {
        let data = try TolerantJSON.encode(theme)
        guard theme.animation == .preset(theme.animation.preset),
              var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        dict["animation"] = ["preset": theme.animation.preset]
        return try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// An animation preset named in the file becomes the base its explicit values override.
    func readTheme(_ url: URL) -> Theme {
        var defaults = Theme.classic
        if let data = try? Data(contentsOf: url),
           let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let preset = (raw["animation"] as? [String: Any])?["preset"] as? String {
            defaults.animation = .preset(preset)
        }
        return read(url, defaults: defaults)
    }

    private func read<T: Codable>(_ url: URL, defaults: T) -> T {
        do {
            return try TolerantJSON.decode(T.self, from: Data(contentsOf: url), defaults: defaults)
        } catch {
            report("\(url.lastPathComponent): \(TolerantJSON.describe(error)) — using defaults")
            return defaults
        }
    }

    private func writeIfMissing<T: Encodable>(_ url: URL, _ make: () -> T) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do { try TolerantJSON.encode(make()).write(to: url, options: .atomic) }
        catch { report("\(url.lastPathComponent): could not create (\(error.localizedDescription))") }
    }

    private func report(_ message: String) {
        problems.append(message)
        Log.error(message)
    }
}
