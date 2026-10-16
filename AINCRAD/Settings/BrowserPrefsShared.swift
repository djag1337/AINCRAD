import SwiftUI

// MIRRORED FILE: this exact file lives in both AINCRAD-Browser (Browser/) and AINCRAD (AINCRAD/Settings/).
// Edit one, copy it to the other. It holds the browser's preferences, their storage and the settings form,
// so AINCRAD's Settings and the browser's own window are literally the same page.

struct BrowserPrefs: Codable, Equatable {
    /// "follow" uses AINCRAD's current theme; otherwise the id of a theme in AINCRAD's themes folder.
    var theme = "follow"
    /// "auto" (about 80% of the screen), "compact" or "large".
    var windowSize = "auto"
    var searchEngine = "duckduckgo"
    var customSearchTemplate = "https://example.com/search?q=%s"

    // Protection
    var blockTrackers = true
    var extraBlockedDomains = ""
    var upgradeHTTPS = true
    var stripTrackingParams = true
    var blockPopups = true
    var blockAutoplay = false

    // Pages
    var darkPages = false
    var defaultZoom = 1.0
    var userAgent = "default"
    var userCSS = ""

    // Reader
    var readerFontSize = 20.0
    var readerWidth = 680.0
    var readerSerif = true

    // Start page and tabs
    var showFavorites = true
    var showRecent = true
    var showClock = true
    var newTabPage = "start"
    var restoreSession = true
    var rememberWindowSize = true
    var floatingToolbar = true
    var autoHideToolbar = true
    /// Toolbar button size as a multiple of the launcher's circle (1.0 = same size).
    var toolbarSize = 1.0

    /// Themes found in AINCRAD's themes folder, as (id, name).
    static func availableThemes() -> [(id: String, name: String)] {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AINCRAD/themes")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            let id = url.deletingPathExtension().lastPathComponent
            let name = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["name"] as? String
            return (id, name ?? id)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static let engines: [(id: String, name: String, template: String)] = [
        ("duckduckgo", "DuckDuckGo", "https://duckduckgo.com/?q=%s"),
        ("google", "Google", "https://www.google.com/search?q=%s"),
        ("bing", "Bing", "https://www.bing.com/search?q=%s"),
        ("brave", "Brave Search", "https://search.brave.com/search?q=%s"),
        ("ecosia", "Ecosia", "https://www.ecosia.org/search?q=%s"),
        ("startpage", "Startpage", "https://www.startpage.com/do/search?q=%s"),
        ("kagi", "Kagi", "https://kagi.com/search?q=%s"),
    ]

    static let userAgents: [(id: String, name: String, string: String?)] = [
        ("default", "Safari (default)", nil),
        ("chrome", "Chrome", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"),
        ("firefox", "Firefox", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:132.0) Gecko/20100101 Firefox/132.0"),
        ("iphone", "iPhone (mobile sites)", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"),
    ]

    /// The search page for some typed words.
    func searchURL(for query: String) -> URL? {
        let template = searchEngine == "custom" ? customSearchTemplate : (Self.engines.first { $0.id == searchEngine }?.template ?? Self.engines[0].template)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }

    var userAgentString: String? { Self.userAgents.first { $0.id == userAgent }?.string }

    var blockedDomains: [String] {
        extraBlockedDomains.split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { $0.contains(".") }
    }
}

/// Reads and writes the shared preferences file, and tells the other app when it changes.
final class BrowserPrefsModel: ObservableObject {
    static let shared = BrowserPrefsModel()
    static let changedName = Notification.Name("com.djag.aincrad.browser.prefsChanged")
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AINCRAD Browser/preferences.json")

    @Published var prefs = BrowserPrefs() {
        didSet { if prefs != oldValue && !loading { save() } }
    }
    private var loading = false
    private var observer: NSObjectProtocol?

    init() {
        reload()
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.changedName, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    func reload() {
        guard let data = try? Data(contentsOf: Self.fileURL), let value = Self.decode(data) else { return }
        guard value != prefs else { return }
        loading = true
        prefs = value
        loading = false
        NotificationCenter.default.post(name: .browserPrefsChanged, object: nil)
    }

    /// Reads the file over the defaults, so a file saved by an older version (missing newer keys) still loads.
    private static func decode(_ data: Data) -> BrowserPrefs? {
        guard let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let base = (try? JSONEncoder().encode(BrowserPrefs())).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: base.merging(saved) { _, new in new }) else { return nil }
        return try? JSONDecoder().decode(BrowserPrefs.self, from: merged)
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(prefs) { try? data.write(to: Self.fileURL, options: .atomic) }
        NotificationCenter.default.post(name: .browserPrefsChanged, object: nil)
        DistributedNotificationCenter.default().postNotificationName(Self.changedName, object: nil, userInfo: nil, deliverImmediately: true)
    }
}

extension Notification.Name {
    static let browserPrefsChanged = Notification.Name("AINCRADBrowserPrefsChanged")
}

/// The browser's whole settings page. Shown inside AINCRAD Settings and in the browser's own window.
struct BrowserPrefsForm: View {
    @ObservedObject var model = BrowserPrefsModel.shared

    private func bind<T>(_ path: WritableKeyPath<BrowserPrefs, T>) -> Binding<T> {
        Binding(get: { model.prefs[keyPath: path] }, set: { model.prefs[keyPath: path] = $0 })
    }

    var body: some View {
        Group {
            Section {
                Picker("Browser theme", selection: bind(\.theme)) {
                    Text("Follow AINCRAD (default)").tag("follow")
                    ForEach(BrowserPrefs.availableThemes(), id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker("New window size", selection: bind(\.windowSize)) {
                    Text("Automatic (about 90% of the screen)").tag("auto")
                    Text("Compact").tag("compact")
                    Text("Large").tag("large")
                }
                Toggle("Remember each window's size and position", isOn: bind(\.rememberWindowSize))
                Toggle("Floating toolbar (see-through, like the launcher)", isOn: bind(\.floatingToolbar))
                Toggle("Hide the toolbar until the pointer reaches the top (⌘L also shows it)", isOn: bind(\.autoHideToolbar))
                HStack {
                    Text("Toolbar size")
                    Slider(value: bind(\.toolbarSize), in: 0.8...1.6, step: 0.05)
                    Text("\(Int((model.prefs.toolbarSize * 100).rounded()))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Text("By default the browser wears whatever theme AINCRAD uses. Pick one here and the browser keeps it, whatever the launcher does: each part of AINCRAD can have its own theme.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Look") }

            Section("Search") {
                Picker("Search engine", selection: bind(\.searchEngine)) {
                    ForEach(BrowserPrefs.engines, id: \.id) { Text($0.name).tag($0.id) }
                    Text("Custom…").tag("custom")
                }
                if model.prefs.searchEngine == "custom" {
                    TextField("Search URL (use %s for the words)", text: bind(\.customSearchTemplate))
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section {
                Toggle("Block ads and trackers", isOn: bind(\.blockTrackers))
                Toggle("Upgrade http:// pages to https:// when possible", isOn: bind(\.upgradeHTTPS))
                Toggle("Strip tracking tags from links (utm_, fbclid, gclid…)", isOn: bind(\.stripTrackingParams))
                Toggle("Block pop-ups that pages open on their own", isOn: bind(\.blockPopups))
                Toggle("Stop videos from autoplaying", isOn: bind(\.blockAutoplay))
                if model.prefs.blockTrackers {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Also block these sites (one per line)").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: bind(\.extraBlockedDomains))
                            .font(.system(.callout, design: .monospaced)).frame(height: 54)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    }
                }
                Text("Blocking uses WebKit's built-in content rules, so nothing you browse is sent anywhere. Changes apply to pages you open next.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Protection") }

            Section {
                Toggle("Dark mode for every page", isOn: bind(\.darkPages))
                HStack {
                    Text("Default page zoom")
                    Slider(value: bind(\.defaultZoom), in: 0.7...2.0, step: 0.1)
                    Text("\(Int((model.prefs.defaultZoom * 100).rounded()))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Picker("Appear to websites as", selection: bind(\.userAgent)) {
                    ForEach(BrowserPrefs.userAgents, id: \.id) { Text($0.name).tag($0.id) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your own CSS, applied to every page").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: bind(\.userCSS))
                        .font(.system(.callout, design: .monospaced)).frame(height: 64)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                }
            } header: { Text("Pages") }

            Section {
                HStack {
                    Text("Text size")
                    Slider(value: bind(\.readerFontSize), in: 14...32, step: 1)
                    Text("\(Int(model.prefs.readerFontSize)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                HStack {
                    Text("Column width")
                    Slider(value: bind(\.readerWidth), in: 440...960, step: 20)
                    Text("\(Int(model.prefs.readerWidth)) px").monospacedDigit().frame(width: 56, alignment: .trailing)
                }
                Toggle("Serif text", isOn: bind(\.readerSerif))
                Text("Reader mode (⌘⇧R) strips a page down to its article, in your AINCRAD theme's colours.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Reader mode") }

            Section {
                Toggle("Show favourites as circles", isOn: bind(\.showFavorites))
                Toggle("Show recently visited sites", isOn: bind(\.showRecent))
                Toggle("Show the clock", isOn: bind(\.showClock))
                Picker("New tabs open", selection: bind(\.newTabPage)) {
                    Text("The start page").tag("start")
                    Text("A blank page").tag("blank")
                }
                Toggle("Reopen last session's tabs on launch", isOn: bind(\.restoreSession))
            } header: { Text("Start page and tabs") }
        }
    }
}
