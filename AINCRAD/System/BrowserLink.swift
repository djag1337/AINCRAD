import AppKit

/// AINCRAD's side of the link with AINCRAD Browser (a separate app): web links can open there,
/// the launcher lists its open tabs, bookmarks and history, its finished downloads become SAO
/// bubbles, and AINCRAD tells it when the theme changes so both look the same. No permissions:
/// the browser writes a small file and both apps announce changes with macOS distributed
/// notifications (visible to apps on this Mac only). Private browser windows are never shared.
enum BrowserLink {
    static let bundleID = "com.djag.aincrad.browser"
    static let themeChanged = Notification.Name("com.djag.aincrad.themeChanged")
    static let browserChanged = Notification.Name("com.djag.aincrad.browser.changed")
    static let downloadFinished = Notification.Name("com.djag.aincrad.browser.downloadFinished")

    static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    static var isInstalled: Bool { appURL != nil }
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    /// Tells the browser (if running) to re-read AINCRAD's theme and player name.
    static func announceTheme() {
        DistributedNotificationCenter.default().postNotificationName(themeChanged, object: nil, userInfo: nil, deliverImmediately: true)
    }

    // MARK: What the browser shares

    struct Tab: Codable { let window: Int; let index: Int; let title: String; let url: String; let selected: Bool }
    struct Item: Codable { let title: String; let url: String }
    struct Snapshot: Codable { var version = 1; let tabs: [Tab]; let bookmarks: [Item]; let history: [Item] }

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AINCRAD Browser/link.json")
    }

    static func snapshot() -> Snapshot? {
        (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
    }

    // MARK: Launcher menu

    static func menuItem() -> MenuItem? {
        guard isInstalled else { return nil }
        return MenuItem(id: "browser:root", name: "AINCRAD Browser", icon: appURL.map { "app:" + $0.path } ?? "sf:globe",
                        provider: "browser:root", description: "Your open tabs, bookmarks and history in AINCRAD Browser.")
    }

    static func children(_ provider: String) -> [MenuItem] {
        let snap = snapshot()
        switch provider {
        case "browser:root":
            let tabCount = isRunning ? (snap?.tabs.count ?? 0) : 0
            return [
                MenuItem(id: "browser:tabs", name: tabCount > 0 ? "Open Tabs (\(tabCount))" : "Open Tabs", icon: "sf:square.on.square", provider: "browser:tabs"),
                MenuItem(id: "browser:bookmarks", name: "Bookmarks", icon: "sf:bookmark.fill", provider: "browser:bookmarks"),
                MenuItem(id: "browser:history", name: "History", icon: "sf:clock.fill", provider: "browser:history"),
                MenuItem(id: "browser:new", name: "New Tab", icon: "sf:plus", action: .url("aincrad-browser://new")),
                MenuItem(id: "browser:private", name: "New Private Window", icon: "sf:eye.slash.fill", action: .url("aincrad-browser://private"),
                         description: "Private windows are never shared with AINCRAD."),
            ]
        case "browser:tabs":
            let tabs = isRunning ? (snap?.tabs ?? []) : []
            if tabs.isEmpty { return [MenuItem(id: "browser:notabs", name: isRunning ? "No open tabs" : "AINCRAD Browser isn't open", icon: "sf:square.dashed")] }
            return tabs.prefix(30).map { t in
                MenuItem(id: "browser:tab:\(t.window):\(t.index)", name: t.title, icon: t.selected ? "sf:checkmark.circle.fill" : "sf:globe",
                         action: .url("aincrad-browser://tab?window=\(t.window)&index=\(t.index)"), description: host(t.url))
            }
        case "browser:bookmarks", "browser:history":
            let list = (provider == "browser:bookmarks" ? snap?.bookmarks : snap?.history) ?? []
            if list.isEmpty { return [MenuItem(id: provider + ":none", name: "Nothing here yet", icon: "sf:tray")] }
            return list.prefix(30).map { i in
                MenuItem(id: provider + ":" + i.url, name: i.title.isEmpty ? host(i.url) : i.title,
                         icon: provider == "browser:bookmarks" ? "sf:bookmark" : "sf:clock", action: .url(i.url), description: host(i.url))
            }
        default: return []
        }
    }

    private static func host(_ s: String) -> String { URL(string: s)?.host ?? s }

    // MARK: Opening web pages

    /// Opens http(s) links in AINCRAD Browser when that's switched on and it's installed.
    static func open(_ url: URL, preferBrowser: Bool) -> Bool {
        guard preferBrowser, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let app = appURL else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
        return true
    }
}
