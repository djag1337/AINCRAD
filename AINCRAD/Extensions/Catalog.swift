import AppKit
import CryptoKit

/// A catalog is a JSON index plus packages and preview images next to it, served from a folder
/// or any web host (e.g. a GitHub repo's raw files). Paths in the index are relative to it.
struct CatalogIndex: Codable {
    var schemaVersion = 1
    var name: String
    var description: String?
    var items: [CatalogItem]
}

struct CatalogItem: Codable, Identifiable, Equatable {
    var id: String
    /// "theme" (a theme .json) or "extension" (an .aincrad package).
    var type: String
    var name: String
    var author: String?
    var version: String
    var description: String?
    var preview: String?
    var package: String
    var sha256: String
    var permissions: [String]?
    var tags: [String]?
}

@MainActor
final class CatalogModel: ObservableObject {
    enum Status: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var index: CatalogIndex?
    @Published private(set) var status: Status = .idle
    @Published private(set) var previews: [String: NSImage] = [:]
    @Published var filter = "all"
    @Published var search = ""

    private let store: ConfigStore
    private let extensions: ExtensionManager
    var installPackage: (URL) -> Void = { _ in }
    var onThemeInstalled: () -> Void = {}
    private(set) var base: URL?

    init(store: ConfigStore, extensions: ExtensionManager) {
        self.store = store
        self.extensions = extensions
    }

    static var defaultLocalCatalog: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/AINCRAD-catalog/catalog.json")
    }

    /// The configured catalog. Nothing is opened automatically: ~/Documents is privacy-protected,
    /// so a local catalog there is only read after the user picks it.
    var catalogURL: URL? {
        let s = store.settings.catalogURL.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if s.hasPrefix("/") || s.hasPrefix("~") { return URL(fileURLWithPath: (s as NSString).expandingTildeInPath) }
        return URL(string: s)
    }

    var visibleItems: [CatalogItem] {
        (index?.items ?? []).filter { item in
            (filter == "all" || item.type == filter)
                && (search.isEmpty || (item.name + " " + (item.description ?? "") + " " + (item.tags ?? []).joined(separator: " "))
                    .localizedCaseInsensitiveContains(search))
        }
    }

    func load() async {
        guard let url = catalogURL else { status = .failed("No catalog chosen yet."); return }
        status = .loading
        Log.info("catalog loading \(url.absoluteString)")
        do {
            let data = try await CatalogModel.fetch(url)
            let idx = try JSONDecoder().decode(CatalogIndex.self, from: data)
            index = idx
            base = url.deletingLastPathComponent()
            status = .loaded
            Log.info("catalog \(url.absoluteString): \(idx.items.count) items")
            for item in idx.items { await loadPreview(item) }
        } catch {
            Log.error("catalog \(url.absoluteString): \(error)")
            status = .failed("Couldn't load the catalog: \(error.localizedDescription)")
        }
    }

    enum InstallState: Equatable { case notInstalled, installed, update }

    func state(_ item: CatalogItem) -> InstallState {
        if item.type == "extension" {
            guard let ext = extensions.extensions.first(where: { $0.id == item.id }) else { return .notInstalled }
            return ext.manifest.version.compare(item.version, options: .numeric) == .orderedAscending ? .update : .installed
        }
        return store.themeIDs().contains(item.id) ? .installed : .notInstalled
    }

    /// Downloads, checks the SHA-256 from the index, then installs through the normal paths.
    func install(_ item: CatalogItem) async -> String? {
        guard let base, let url = URL(string: item.package, relativeTo: base)?.absoluteURL else { return "Bad package path" }
        do {
            let data = try await CatalogModel.fetch(url)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == item.sha256.lowercased() else {
                return "The download doesn't match the catalog's checksum, so it wasn't installed."
            }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try data.write(to: tmp)
            if item.type == "theme" {
                let theme = try TolerantJSON.decode(Theme.self, from: data, defaults: .classic)
                try store.saveTheme(theme, id: item.id)
                onThemeInstalled()
                return "Installed theme “\(item.name)”. Choose it in Themes or the menu bar menu."
            }
            installPackage(tmp)
            return nil
        } catch {
            return "Install failed: \(error.localizedDescription)"
        }
    }

    private func loadPreview(_ item: CatalogItem) async {
        guard let p = item.preview, let base, let url = URL(string: p, relativeTo: base)?.absoluteURL,
              let data = try? await CatalogModel.fetch(url), let img = NSImage(data: data) else { return }
        previews[item.id] = img
    }

    /// Off the main thread: a file read can wait on a macOS privacy prompt, and a download on the network.
    nonisolated static func fetch(_ url: URL) async throws -> Data {
        if url.isFileURL {
            return try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
        }
        guard url.scheme == "https" || url.scheme == "http" else { throw URLError(.unsupportedURL) }
        var req = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)
        req.setValue("AINCRAD", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw URLError(.badServerResponse) }
        return data
    }
}
