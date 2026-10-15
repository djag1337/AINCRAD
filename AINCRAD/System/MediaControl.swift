import AppKit

/// Now Playing for Music and Spotify, through each app's own scripting (macOS asks once per app,
/// the first time). An app is only ever asked when it's already running, so this never launches one.
enum MediaControl {
    struct Player { let app: String; let bundleID: String }
    static let players = [Player(app: "Music", bundleID: "com.apple.Music"), Player(app: "Spotify", bundleID: "com.spotify.client")]

    struct Track { let player: Player; let title: String; let artist: String; let playing: Bool }

    static func isRunning(_ p: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleID).isEmpty
    }

    /// Call off the main thread; scripting a busy app can take a moment.
    static func nowPlaying() -> [Track] {
        players.filter(isRunning).compactMap { p in
            let source = """
            tell application "\(p.app)"
                if player state is stopped then return ""
                return (name of current track) & "\\n" & (artist of current track) & "\\n" & (player state as string)
            end tell
            """
            var error: NSDictionary?
            guard let out = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue, !out.isEmpty else {
                if let error { Log.info("media: \(p.app) script: \(error[NSAppleScript.errorMessage] ?? error)") }
                return nil
            }
            let lines = out.components(separatedBy: "\n")
            return Track(player: p, title: lines[0], artist: lines.count > 1 ? lines[1] : "", playing: lines.count > 2 && lines[2] == "playing")
        }
    }

    static func command(_ verb: String, app: String) {
        guard let p = players.first(where: { $0.app == app }), isRunning(p) else { return }
        let line = ["playpause": "playpause", "next": "next track", "previous": "previous track"][verb] ?? "playpause"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"\(app)\" to \(line)")?.executeAndReturnError(&error)
            if let error { Log.error("media: \(app) \(verb): \(error[NSAppleScript.errorMessage] ?? error)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MediaMenu.shared.invalidate() }
        }
    }
}

final class MediaMenu {
    static let shared = MediaMenu()
    var onUpdate: ((String) -> Void)?
    private var cache: (time: Date, tracks: [MediaControl.Track])?
    private var loading = false

    func invalidate() { cache = nil }

    func children() -> [MenuItem] {
        let running = MediaControl.players.filter(MediaControl.isRunning)
        if running.isEmpty {
            return MediaControl.players.compactMap { p in
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.bundleID) else { return nil }
                return MenuItem(id: "media:open:" + p.app, name: "Open \(p.app)", icon: "app:" + url.path, action: .app(url.path))
            } + [MenuItem(id: "media:none", name: "Nothing playing", icon: "sf:music.note")]
        }
        guard let c = cache, Date().timeIntervalSince(c.time) < 3 else {
            load()
            return [MenuItem(id: "media:loading", name: "Checking…", icon: "sf:hourglass")]
        }
        if c.tracks.isEmpty { return [MenuItem(id: "media:stopped", name: "Nothing playing", icon: "sf:music.note")] }
        return c.tracks.flatMap { t -> [MenuItem] in
            let app = t.player.app
            return [
                MenuItem(id: "media:track:" + app, name: t.title, icon: "sf:music.note", description: "\(t.artist) · \(app)"),
                MenuItem(id: "media:pp:" + app, name: t.playing ? "Pause" : "Play", icon: t.playing ? "sf:pause.fill" : "sf:play.fill",
                         action: .builtin("media:playpause:" + app)),
                MenuItem(id: "media:next:" + app, name: "Next", icon: "sf:forward.fill", action: .builtin("media:next:" + app)),
                MenuItem(id: "media:prev:" + app, name: "Previous", icon: "sf:backward.fill", action: .builtin("media:previous:" + app)),
            ]
        }
    }

    private func load() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tracks = MediaControl.nowPlaying()
            DispatchQueue.main.async {
                self?.loading = false
                self?.cache = (Date(), tracks)
                self?.onUpdate?("media:now")
            }
        }
    }
}
