import AppKit

/// The SAO dock's own pinned items (apps and folders), saved in dock.json. Seeded once from
/// Apple's Dock, then edited from the dock itself (drag, drop, right-click) and the launcher.
final class DockStore {
    static let shared = DockStore(url: ConfigStore.baseDirectory.appendingPathComponent("dock.json"))

    struct Item: Codable, Equatable {
        var path: String
        /// Folders: "name" (default, good for launcher folders) or "added" (newest first, like Downloads).
        var sort: String?
        var url: URL { URL(fileURLWithPath: path) }
        /// A folder (not an app bundle, which is a folder too).
        var isFolder: Bool {
            var dir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue && !path.hasSuffix(".app")
        }
    }

    private let url: URL
    private(set) var items: [Item] = []
    var onChange: (() -> Void)?

    init(url: URL) { self.url = url }

    func load(seed: () -> [Item] = DockStore.seedFromAppleDock) {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        } else {
            items = seed()
            save()
            Log.info("dock: started from Apple's Dock (\(items.count) items)")
        }
    }

    func contains(_ path: String) -> Bool { items.contains { $0.path == path } }

    /// Adds (or moves) `url` to `index`, or the end.
    func add(_ url: URL, at index: Int? = nil) {
        let path = url.standardizedFileURL.path
        items.removeAll { $0.path == path }
        let i = min(max(index ?? items.count, 0), items.count)
        items.insert(Item(path: path), at: i)
        changed("added \(url.lastPathComponent)")
    }

    func remove(_ path: String) {
        guard contains(path) else { return }
        items.removeAll { $0.path == path }
        changed("removed \((path as NSString).lastPathComponent)")
    }

    func setSort(_ path: String, _ sort: String) {
        guard let i = items.firstIndex(where: { $0.path == path }) else { return }
        items[i].sort = sort
        changed("sort \(items[i].url.lastPathComponent) by \(sort)")
    }

    func move(from: Int, to: Int) {
        guard items.indices.contains(from), from != to else { return }
        let item = items.remove(at: from)
        items.insert(item, at: min(max(to, 0), items.count))
        changed("moved \(item.url.lastPathComponent)")
    }

    private func changed(_ what: String) {
        save()
        Log.info("dock: \(what)")
        onChange?()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    /// Apple's Dock apps. Its folders (Downloads and so on) aren't copied; add the ones you
    /// want from the launcher (right-click › Add to Dock) or by dropping them on the dock.
    static func seedFromAppleDock() -> [Item] {
        func paths(_ key: String) -> [Item] {
            guard let raw = CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else { return [] }
            return raw.compactMap { entry in
                guard let tile = entry["tile-data"] as? [String: Any], let file = tile["file-data"] as? [String: Any],
                      let value = file["_CFURLString"] as? String, let u = URL(string: value), u.isFileURL,
                      FileManager.default.fileExists(atPath: u.path) else { return nil }
                return Item(path: u.standardizedFileURL.path)
            }
        }
        return paths("persistent-apps")
    }
}
