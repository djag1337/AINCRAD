import AppKit

/// System-wide changes AINCRAD makes while it runs, each reversible on its own:
/// * hiding Apple's Dock entirely, in every app and Space;
/// * for the always-on SAO bar, macOS's "hide the menu bar in full screen only", so on the desktop
///   the menu bar stays put (windows stop below it) under the SAO bar.
/// They change the same preferences System Settings does. The user's original values are saved to
/// a file first, so turning an option off, quitting, or relaunching after a crash restores them.
enum SystemChrome {
    private struct Saved: Codable {
        var dockAutohide: Bool?
        var dockDelay: Double?
        /// Nil in files from before the menu bar was managed: those only ever saved the Dock.
        var dockSaved: Bool?
        var menuBarHidden: Bool?
        var menuBarInFullScreen: Bool?
        var menuBarSaved: Bool?
    }

    private static var savedURL: URL { ConfigStore.baseDirectory.appendingPathComponent("system-chrome.json") }
    private static let dock = "com.apple.dock" as CFString
    private static let global = kCFPreferencesAnyApplication

    /// `hideMenuBar` wins over `coverMenuBar`: the menu bar is set to auto-hide (windows get the
    /// space) and made fully transparent and click-through, so even its slide-in shows nothing.
    static func update(hideDock: Bool, coverMenuBar: Bool, hideMenuBar: Bool = false) {
        let existing = (try? Data(contentsOf: savedURL)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        var saved = existing ?? Saved()
        if existing != nil && saved.dockSaved == nil && saved.menuBarSaved == nil { saved.dockSaved = true }
        var dockChanged = false, menuChanged = false

        if hideDock {
            if saved.dockSaved != true {
                saved.dockAutohide = value("autohide", dock) as? Bool
                saved.dockDelay = (value("autohide-delay", dock) as? NSNumber)?.doubleValue
                saved.dockSaved = true
                guard write(saved) else { return }
            }
            // Auto-hide with a reveal delay of over a day: the Dock never slides in, even at the edge.
            let a = set("autohide", true as CFBoolean, dock), b = set("autohide-delay", 100_000.0 as CFNumber, dock)
            dockChanged = a || b
        } else if saved.dockSaved == true {
            let a = set("autohide", saved.dockAutohide.map { $0 as CFBoolean }, dock)
            let b = set("autohide-delay", saved.dockDelay.map { $0 as CFNumber }, dock)
            dockChanged = a || b
            saved.dockSaved = nil
        }

        if coverMenuBar || hideMenuBar {
            if saved.menuBarSaved != true {
                saved.menuBarHidden = value("_HIHideMenuBar", global) as? Bool
                saved.menuBarInFullScreen = value("AppleMenuBarVisibleInFullscreen", global) as? Bool
                saved.menuBarSaved = true
                guard write(saved) else { return }
            }
            let a = set("_HIHideMenuBar", hideMenuBar as CFBoolean, global)
            let b = hideMenuBar
                ? set("AppleMenuBarVisibleInFullscreen", saved.menuBarInFullScreen.map { $0 as CFBoolean }, global)
                : set("AppleMenuBarVisibleInFullscreen", false as CFBoolean, global)
            menuChanged = a || b
        } else if saved.menuBarSaved == true {
            let a = set("_HIHideMenuBar", saved.menuBarHidden.map { $0 as CFBoolean }, global)
            let b = set("AppleMenuBarVisibleInFullscreen", saved.menuBarInFullScreen.map { $0 as CFBoolean }, global)
            menuChanged = a || b
            saved.menuBarSaved = nil
        }

        if saved.dockSaved == true || saved.menuBarSaved == true {
            _ = write(saved)
        } else {
            try? FileManager.default.removeItem(at: savedURL)
        }
        commit(dock: dockChanged, menuBar: menuChanged)
        MenuBarAlpha.set(hideMenuBar ? 0 : 1)
        if dockChanged { Log.info("system chrome: Apple Dock \(hideDock ? "hidden" : "restored")") }
        if menuChanged { Log.info("system chrome: menu bar \(hideMenuBar ? "hidden" : coverMenuBar ? "pinned under the SAO bar" : "restored")") }
    }

    static func restoreAll() { update(hideDock: false, coverMenuBar: false) }

    private static func write(_ saved: Saved) -> Bool {
        guard let data = try? JSONEncoder().encode(saved), (try? data.write(to: savedURL, options: .atomic)) != nil else {
            Log.error("system chrome: couldn't save the original settings; leaving them alone")
            return false
        }
        return true
    }

    private static func value(_ key: String, _ app: CFString) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, app)
    }

    /// Writes `value` (nil removes the key). Returns whether anything changed.
    private static func set(_ key: String, _ value: CFPropertyList?, _ app: CFString) -> Bool {
        let old = CFPreferencesCopyAppValue(key as CFString, app)
        if let old, let value, CFEqual(old, value) { return false }
        if old == nil && value == nil { return false }
        CFPreferencesSetAppValue(key as CFString, value, app)
        return true
    }

    private static func commit(dock: Bool, menuBar: Bool) {
        if dock {
            CFPreferencesAppSynchronize(self.dock)
            // The Dock only reads its preferences at launch; launchd restarts it straight away.
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            kill.arguments = ["Dock"]
            try? kill.run()
        }
        if menuBar {
            CFPreferencesAppSynchronize(global)
            // What System Settings posts when the menu bar's auto-hide changes; running apps re-read it.
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("AppleInterfaceMenuBarHidingChangedNotification"), object: nil, userInfo: nil, deliverImmediately: true)
        }
    }
}

/// The menu bar's opacity, through WindowServer's private SkyLight call (as yabai's
/// `menubar_opacity` does). At 0 the menu bar draws nothing and ignores the mouse. It isn't a saved
/// setting: it lasts while AINCRAD runs, and AINCRAD sets it back to 1 when the option is off or it quits.
enum MenuBarAlpha {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetInsetAndAlpha = @convention(c) (Int32, Double, Double, Float) -> Int32
    private static var current: Float = 1
    private static let calls: (MainConnection, SetInsetAndAlpha)? = {
        guard let lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let main = dlsym(lib, "SLSMainConnectionID"), let set = dlsym(lib, "SLSSetMenuBarInsetAndAlpha") else { return nil }
        return (unsafeBitCast(main, to: MainConnection.self), unsafeBitCast(set, to: SetInsetAndAlpha.self))
    }()

    static func set(_ alpha: Float) {
        guard alpha != current else { return }
        guard let (main, setAlpha) = calls else {
            Log.error("menu bar: SkyLight call unavailable on this macOS")
            return
        }
        _ = setAlpha(main(), 0, 1, alpha)
        current = alpha
        Log.info("menu bar: opacity \(alpha)")
    }
}
