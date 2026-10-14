import Foundation

/// First-run menu; only references things that exist on this Mac.
enum DefaultMenu {
    static func build() -> MenuFile {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        func app(_ path: String) -> MenuItem? {
            guard fm.fileExists(atPath: path) else { return nil }
            return MenuItem(name: AppScanner.displayName(path), action: .app(path))
        }
        func place(_ name: String, _ path: String, _ symbol: String) -> MenuItem? {
            guard fm.fileExists(atPath: path) else { return nil }
            return MenuItem(name: name, icon: "sf:\(symbol)", action: .open(path))
        }

        let favorites = [
            "/System/Library/CoreServices/Finder.app",
            "/Applications/Safari.app",
            "/System/Applications/Utilities/Terminal.app",
            "/System/Applications/System Settings.app",
            "/System/Applications/Music.app",
        ].compactMap(app)

        let places = [
            place("Home", home, "house.fill"),
            place("Desktop", home + "/Desktop", "menubar.dock.rectangle"),
            place("Documents", home + "/Documents", "doc.fill"),
            place("Downloads", home + "/Downloads", "arrow.down.circle.fill"),
            place("Applications", "/Applications", "square.grid.2x2.fill"),
        ].compactMap { $0 }

        let web = [
            MenuItem(name: "YouTube", icon: "sf:play.rectangle.fill", action: .url("https://www.youtube.com")),
            MenuItem(name: "GitHub", icon: "sf:chevron.left.forwardslash.chevron.right", action: .url("https://github.com")),
            MenuItem(name: "SAO Wiki", icon: "sf:book.fill", action: .url("https://swordartonline.fandom.com")),
        ]

        let utilities = [
            "/System/Applications/Utilities/Activity Monitor.app",
            "/System/Applications/Utilities/Console.app",
            "/System/Applications/Utilities/Disk Utility.app",
            "/System/Applications/Utilities/Terminal.app",
        ].compactMap(app)

        let system = [
            MenuItem(name: "Utilities", icon: "sf:wrench.and.screwdriver.fill", children: utilities),
            MenuItem(name: "AINCRAD Settings", icon: "sf:slider.horizontal.3", action: .builtin("settings")),
            MenuItem(name: "Edit Menu Config", icon: "sf:square.and.pencil", action: .builtin("openConfig")),
            MenuItem(name: "Reload Config", icon: "sf:arrow.clockwise", action: .builtin("reload")),
            MenuItem(name: "Pause Activation", icon: "sf:pause.fill", action: .builtin("pause")),
            MenuItem(name: "Log Out of AINCRAD", icon: "sf:power", action: .builtin("quit")),
        ]

        return MenuFile(root: [
            MenuItem(name: "Favorites", icon: "sf:star.fill", children: favorites),
            MenuItem(name: "Applications", icon: "sf:square.grid.3x3.fill", provider: "appCategories"),
            MenuItem(name: "Games", icon: "sf:gamecontroller.fill", provider: "games"),
            MenuItem(name: "Recent", icon: "sf:clock.fill", provider: "recentApps"),
            MenuItem(name: "Places", icon: "sf:folder.fill", children: places),
            MenuItem(name: "Web", icon: "sf:globe", children: web),
            MenuItem(name: "System", icon: "sf:gearshape.fill", children: system),
        ])
    }
}

enum AppScanner {
    static func displayName(_ path: String) -> String {
        let n = FileManager.default.displayName(atPath: path)
        return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
    }

    struct Entry { let name: String; let path: String; let category: String? }

    static func scan() -> [MenuItem] {
        entries().map { MenuItem(id: "app:" + $0.path, name: $0.name, action: .app($0.path)) }
    }

    /// Groups, in menu order: (title, SF Symbol, LSApplicationCategoryType values).
    static let groups: [(String, String, [String])] = [
        ("Games", "gamecontroller.fill", ["games"]),
        ("Developer Tools", "hammer.fill", ["developer-tools"]),
        ("Graphics & Design", "paintbrush.pointed.fill", ["graphics-design", "photography"]),
        ("Music & Video", "play.rectangle.fill", ["music", "video", "entertainment"]),
        ("Productivity", "doc.richtext.fill", ["productivity", "business", "finance", "education", "reference"]),
        ("Social", "bubble.left.and.bubble.right.fill", ["social-networking", "news"]),
        ("Utilities", "wrench.and.screwdriver.fill", ["utilities"]),
    ]

    /// Applications sorted into SAO Utils-style categories, plus "All A–Z" first.
    static func categorized() -> [MenuItem] {
        let all = entries()
        var buckets: [String: [Entry]] = [:]
        for e in all {
            let cat = (e.category ?? "").replacingOccurrences(of: "public.app-category.", with: "")
            let group = groups.first { g in g.2.contains { cat == $0 || cat.hasSuffix("-" + $0) } }?.0
                ?? (e.path.hasPrefix("/System/") ? "System" : "Other")
            buckets[group, default: []].append(e)
        }
        func items(_ list: [Entry]) -> [MenuItem] {
            list.map { MenuItem(id: "app:" + $0.path, name: $0.name, action: .app($0.path)) }
        }
        var menu = [MenuItem(id: "apps:all", name: "All A–Z", icon: "sf:textformat.abc", children: items(all))]
        let order = groups.map { ($0.0, $0.1) } + [("System", "apple.logo"), ("Other", "square.grid.2x2.fill")]
        for (title, symbol) in order {
            guard let list = buckets[title], !list.isEmpty else { continue }
            menu.append(MenuItem(id: "apps:" + title, name: title, icon: "sf:" + symbol, children: items(list),
                                 description: "\(list.count) app\(list.count == 1 ? "" : "s")"))
        }
        return menu
    }

    /// Top-level apps plus one folder level (e.g. /Applications/Utilities, vendor folders).
    /// Categories come from each app's Info.plist (read directly; NSBundle would cache them all).
    static func entries() -> [Entry] {
        let fm = FileManager.default
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var seen = Set<String>()
        var out: [Entry] = []

        func visit(_ dir: String, depth: Int) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for n in names where !n.hasPrefix(".") {
                let path = dir + "/" + n
                if n.hasSuffix(".app") {
                    let name = displayName(path)
                    if seen.insert(name).inserted {
                        let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
                        out.append(Entry(name: name, path: path, category: info?["LSApplicationCategoryType"] as? String))
                    }
                } else if depth == 0 {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { visit(path, depth: 1) }
                }
            }
        }
        roots.forEach { visit($0, depth: 0) }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
