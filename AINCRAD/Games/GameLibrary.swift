import Foundation

/// Finds installed games across launchers: Steam (every library folder), Heroic (GOG and Epic),
/// Prism Launcher instances (Minecraft), and apps that declare themselves games.
/// Read-only; runs off the main thread because a library can live in iCloud Drive.
enum GameLibrary {
    struct Game: Equatable {
        var id: String
        var title: String
        var source: String
        var action: MenuAction
        /// Poster art (2:3) when the launcher keeps one.
        var cover: String?
        var icon: String?

        var menuItem: MenuItem {
            MenuItem(id: "game:" + id, name: title, icon: icon ?? cover.map { "image:" + $0 }, action: action,
                     description: "\(source) game")
        }
    }

    static let sources: [(name: String, symbol: String)] = [
        ("Steam", "cloud.fill"), ("GOG", "circle.hexagongrid.fill"), ("Epic", "e.circle.fill"),
        ("Minecraft", "cube.fill"), ("Apps", "app.fill"),
    ]

    static func scan() -> [Game] {
        (steam() + heroic() + prism() + apps()).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Menu: "All Games" first, then one submenu per launcher that has any.
    static func menu(_ games: [Game]) -> [MenuItem] {
        guard !games.isEmpty else { return [] }
        var out = [MenuItem(id: "games:all", name: "All Games", icon: "sf:gamecontroller.fill", children: games.map(\.menuItem))]
        for s in sources {
            let list = games.filter { $0.source == s.name }
            if !list.isEmpty {
                out.append(MenuItem(id: "games:" + s.name, name: s.name, icon: "sf:" + s.symbol, children: list.map(\.menuItem),
                                    description: "\(list.count) game\(list.count == 1 ? "" : "s")"))
            }
        }
        return out
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path
    private static let fm = FileManager.default

    // MARK: Steam

    /// Tools Steam installs alongside games.
    private static let steamTools = ["Redistributable", "Steamworks", "Proton", "Steam Linux Runtime", "SDK", "Dedicated Server"]

    static func steam() -> [Game] {
        let root = home + "/Library/Application Support/Steam"
        guard let vdf = try? String(contentsOfFile: root + "/steamapps/libraryfolders.vdf", encoding: .utf8) else { return [] }
        var libraries = values(for: "path", in: vdf)
        if libraries.isEmpty { libraries = [root] }
        var games: [Game] = []
        for lib in Set(libraries) {
            let apps = lib + "/steamapps"
            for file in (try? fm.contentsOfDirectory(atPath: apps)) ?? [] where file.hasPrefix("appmanifest_") && file.hasSuffix(".acf") {
                guard let acf = try? String(contentsOfFile: apps + "/" + file, encoding: .utf8),
                      let id = values(for: "appid", in: acf).first, let name = values(for: "name", in: acf).first,
                      !steamTools.contains(where: { name.contains($0) }) else { continue }
                let cache = root + "/appcache/librarycache/" + id
                let cover = ["/library_600x900.jpg", "/library_600x900_2x.jpg", "/header.jpg"].map { cache + $0 }.first { fm.fileExists(atPath: $0) }
                games.append(Game(id: "steam:" + id, title: name, source: "Steam", action: .url("steam://rungameid/" + id), cover: cover))
            }
        }
        return games
    }

    /// `"key"   "value"` pairs from Valve's KeyValues text format.
    static func values(for key: String, in text: String) -> [String] {
        let pattern = "\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s+\"((?:[^\"\\\\]|\\\\.)*)\""
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]).replacingOccurrences(of: "\\\\", with: "\\") }
        }
    }

    // MARK: Heroic (GOG, Epic)

    static func heroic() -> [Game] {
        let root = home + "/Library/Application Support/heroic"
        var games: [Game] = []
        if let data = fm.contents(atPath: root + "/gog_store/installed.json"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let installed = json["installed"] as? [[String: Any]] {
            for g in installed where (g["is_dlc"] as? Bool) != true {
                guard let appName = g["appName"] as? String else { continue }
                let path = g["install_path"] as? String ?? ""
                let title = (g["title"] as? String) ?? (path as NSString).lastPathComponent
                games.append(Game(id: "gog:" + appName, title: title.isEmpty ? appName : title, source: "GOG",
                                  action: .url("heroic://launch?appName=\(appName)&runner=gog"), cover: nil, icon: "sf:gamecontroller.fill"))
            }
        }
        if let data = fm.contents(atPath: root + "/legendaryConfig/legendary/installed.json"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (appName, value) in json {
                guard let g = value as? [String: Any], (g["is_dlc"] as? Bool) != true else { continue }
                games.append(Game(id: "epic:" + appName, title: g["title"] as? String ?? appName, source: "Epic",
                                  action: .url("heroic://launch?appName=\(appName)&runner=legendary"), cover: nil, icon: "sf:gamecontroller.fill"))
            }
        }
        return games
    }

    // MARK: Prism Launcher (Minecraft)

    static func prism() -> [Game] {
        let root = home + "/Library/Application Support/PrismLauncher/instances"
        return ((try? fm.contentsOfDirectory(atPath: root)) ?? []).compactMap { folder in
            guard let cfg = try? String(contentsOfFile: "\(root)/\(folder)/instance.cfg", encoding: .utf8) else { return nil }
            let name = cfg.split(separator: "\n").first { $0.hasPrefix("name=") }.map { String($0.dropFirst(5)) } ?? folder
            return Game(id: "prism:" + folder, title: name, source: "Minecraft", action: .builtin("prism:" + folder),
                        cover: nil, icon: "sf:cube.fill")
        }
    }

    // MARK: Apps tagged as games

    static func apps() -> [Game] {
        AppScanner.entries().filter { ($0.category ?? "").contains("games") }.map {
            Game(id: "app:" + $0.path, title: $0.name, source: "Apps", action: .app($0.path), cover: nil, icon: "app:" + $0.path)
        }
    }
}
