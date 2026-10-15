import AppKit

/// macOS settings AINCRAD can change itself: the same preference keys System Settings writes,
/// followed by the restart or notification that makes them take effect. A few only apply after
/// logging out, and say so. Everything else is a link to the right System Settings page.
struct MacSetting {
    enum Kind {
        case toggle(on: CFPropertyList, off: CFPropertyList, defaultOn: Bool)
        /// Options in order. A nil value means "remove the key" (the macOS default).
        case choice([(label: String, value: CFPropertyList?)], defaultIndex: Int)
    }

    let id: String
    let title: String
    let section: String
    /// Short row label inside its section (the column is narrow); `title` is used in messages.
    var label: String { MacSettings.labels[id] ?? title }
    /// "-g" for the global domain.
    let domain: String
    let key: String
    var currentHost = false
    let kind: Kind
    /// Process to restart so the change shows ("Dock", "Finder", "SystemUIServer").
    var restart: String? = nil
    /// Distributed notification that makes running apps pick the change up.
    var notify: String? = nil
    /// Applies only after logging out.
    var needsLogout = false
    /// Extra domains that take the same key and value (trackpads have two).
    var alsoDomains: [String] = []
    /// AINCRAD manages this itself when the condition holds (e.g. Hide Apple's Dock).
    var managedBy: ((AppSettings) -> String?)? = nil
}

enum MacSettings {
    private static func cfDomain(_ d: String) -> CFString { d == "-g" ? kCFPreferencesAnyApplication : d as CFString }

    static func read(_ s: MacSetting) -> CFPropertyList? {
        s.currentHost
            ? CFPreferencesCopyValue(s.key as CFString, cfDomain(s.domain), kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            : CFPreferencesCopyAppValue(s.key as CFString, cfDomain(s.domain))
    }

    private static func equal(_ a: CFPropertyList?, _ b: CFPropertyList?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?):
            // Bools and numbers are both CFNumber-ish in preferences; compare by value.
            if let nx = x as? NSNumber, let ny = y as? NSNumber { return nx.doubleValue == ny.doubleValue }
            return CFEqual(x, y)
        default: return false
        }
    }

    static func isOn(_ s: MacSetting) -> Bool {
        guard case .toggle(let on, _, let defaultOn) = s.kind else { return false }
        guard let v = read(s) else { return defaultOn }
        return equal(v, on)
    }

    /// The index of the current choice (the default when the key isn't set or doesn't match).
    static func choiceIndex(_ s: MacSetting) -> Int {
        guard case .choice(let options, let def) = s.kind else { return 0 }
        let v = read(s)
        return options.firstIndex { equal($0.value, v) } ?? (v == nil ? def : def)
    }

    /// `restartNow: false` lets a profile write several settings and restart each process once.
    static func write(_ s: MacSetting, _ value: CFPropertyList?, restartNow: Bool = true) {
        for domain in [s.domain] + s.alsoDomains {
            if s.currentHost {
                CFPreferencesSetValue(s.key as CFString, value, cfDomain(domain), kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
                CFPreferencesSynchronize(cfDomain(domain), kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            } else {
                CFPreferencesSetAppValue(s.key as CFString, value, cfDomain(domain))
                CFPreferencesAppSynchronize(cfDomain(domain))
            }
        }
        if let n = s.notify {
            DistributedNotificationCenter.default().postNotificationName(NSNotification.Name(n), object: nil, userInfo: nil, deliverImmediately: true)
        }
        if restartNow, let p = s.restart { restart(p) }
        Log.info("mac settings: \(s.id) = \(value.map { "\($0)" } ?? "default")")
    }

    static func restart(_ process: String) {
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        kill.arguments = [process]
        try? kill.run()
    }

    // MARK: The table

    private static let corners: [(label: String, value: CFPropertyList?)] = [
        ("Nothing", 1 as CFNumber), ("Mission Control", 2 as CFNumber), ("Application Windows", 3 as CFNumber),
        ("Desktop", 4 as CFNumber), ("Notification Center", 12 as CFNumber), ("Launchpad", 11 as CFNumber),
        ("Quick Note", 14 as CFNumber), ("Start Screen Saver", 5 as CFNumber), ("Put Display to Sleep", 10 as CFNumber),
        ("Lock Screen", 13 as CFNumber),
    ]

    private static func home(_ sub: String) -> CFString { (NSHomeDirectory() + "/" + sub) as CFString }

    static let all: [MacSetting] = [
        // Dock & Menu Bar
        MacSetting(id: "dock-autohide", title: "Automatically Hide Dock", section: "dock", domain: "com.apple.dock", key: "autohide",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: false), restart: "Dock",
                   managedBy: { $0.hideAppleDock || ($0.shellModeEnabled && $0.shellReplaceSystem) ? "AINCRAD is hiding the Dock" : nil }),
        MacSetting(id: "dock-size", title: "Dock Size", section: "dock", domain: "com.apple.dock", key: "tilesize",
                   kind: .choice([("Small", 36 as CFNumber), ("Medium", 48 as CFNumber), ("Large", 64 as CFNumber), ("Extra Large", 80 as CFNumber)], defaultIndex: 1),
                   restart: "Dock"),
        MacSetting(id: "dock-magnify", title: "Magnification", section: "dock", domain: "com.apple.dock", key: "magnification",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: false), restart: "Dock"),
        MacSetting(id: "dock-position", title: "Dock Position", section: "dock", domain: "com.apple.dock", key: "orientation",
                   kind: .choice([("Left", "left" as CFString), ("Bottom", "bottom" as CFString), ("Right", "right" as CFString)], defaultIndex: 1),
                   restart: "Dock"),
        MacSetting(id: "dock-minimize", title: "Minimize Effect", section: "dock", domain: "com.apple.dock", key: "mineffect",
                   kind: .choice([("Genie", "genie" as CFString), ("Scale", "scale" as CFString), ("Suck", "suck" as CFString)], defaultIndex: 0),
                   restart: "Dock"),
        MacSetting(id: "dock-recents", title: "Show Recent Apps in Dock", section: "dock", domain: "com.apple.dock", key: "show-recents",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: true), restart: "Dock"),
        MacSetting(id: "menubar-autohide", title: "Automatically Hide Menu Bar", section: "dock", domain: "-g", key: "_HIHideMenuBar",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: false),
                   notify: "AppleInterfaceMenuBarHidingChangedNotification",
                   managedBy: { $0.hideAppleMenuBar || ($0.shellModeEnabled && $0.shellReplaceSystem) ? "AINCRAD manages the menu bar" : nil }),

        // Finder & Desktop
        MacSetting(id: "desktop-icons", title: "Show Desktop Icons", section: "finder", domain: "com.apple.finder", key: "CreateDesktop",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: true), restart: "Finder"),
        MacSetting(id: "hidden-files", title: "Show Hidden Files", section: "finder", domain: "com.apple.finder", key: "AppleShowAllFiles",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: false), restart: "Finder"),
        MacSetting(id: "extensions", title: "Show All File Extensions", section: "finder", domain: "-g", key: "AppleShowAllExtensions",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: false), restart: "Finder"),
        MacSetting(id: "pathbar", title: "Show Path Bar", section: "finder", domain: "com.apple.finder", key: "ShowPathbar",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: false), restart: "Finder"),
        MacSetting(id: "statusbar", title: "Show Status Bar", section: "finder", domain: "com.apple.finder", key: "ShowStatusBar",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: false), restart: "Finder"),
        MacSetting(id: "folders-first", title: "Keep Folders on Top", section: "finder", domain: "com.apple.finder", key: "_FXSortFoldersFirst",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: false), restart: "Finder"),
        MacSetting(id: "click-desktop", title: "Click Wallpaper to Reveal Desktop", section: "finder", domain: "com.apple.WindowManager",
                   key: "EnableStandardClickToShowDesktop", kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: true)),

        // Mission Control
        MacSetting(id: "mru-spaces", title: "Rearrange Spaces by Recent Use", section: "spaces", domain: "com.apple.dock", key: "mru-spaces",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: true), restart: "Dock"),
        MacSetting(id: "group-apps", title: "Group Windows by App", section: "spaces", domain: "com.apple.dock", key: "expose-group-apps",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: false), restart: "Dock"),
        MacSetting(id: "separate-spaces", title: "Displays Have Separate Spaces", section: "spaces", domain: "com.apple.spaces", key: "spans-displays",
                   kind: .toggle(on: false as CFBoolean, off: true as CFBoolean, defaultOn: true), needsLogout: true),
        MacSetting(id: "corner-tl", title: "Hot Corner: Top Left", section: "corners", domain: "com.apple.dock", key: "wvous-tl-corner",
                   kind: .choice(corners, defaultIndex: 0), restart: "Dock"),
        MacSetting(id: "corner-tr", title: "Hot Corner: Top Right", section: "corners", domain: "com.apple.dock", key: "wvous-tr-corner",
                   kind: .choice(corners, defaultIndex: 0), restart: "Dock"),
        MacSetting(id: "corner-bl", title: "Hot Corner: Bottom Left", section: "corners", domain: "com.apple.dock", key: "wvous-bl-corner",
                   kind: .choice(corners, defaultIndex: 0), restart: "Dock"),
        MacSetting(id: "corner-br", title: "Hot Corner: Bottom Right", section: "corners", domain: "com.apple.dock", key: "wvous-br-corner",
                   kind: .choice(corners, defaultIndex: 6), restart: "Dock"),

        // Keyboard & Trackpad
        MacSetting(id: "key-repeat", title: "Key Repeat Speed", section: "input", domain: "-g", key: "KeyRepeat",
                   kind: .choice([("Fastest", 2 as CFNumber), ("Fast", 6 as CFNumber), ("Normal", 12 as CFNumber), ("Slow", 30 as CFNumber)], defaultIndex: 1),
                   needsLogout: true),
        MacSetting(id: "repeat-delay", title: "Delay Until Repeat", section: "input", domain: "-g", key: "InitialKeyRepeat",
                   kind: .choice([("Short", 15 as CFNumber), ("Medium", 25 as CFNumber), ("Long", 68 as CFNumber)], defaultIndex: 1),
                   needsLogout: true),
        MacSetting(id: "press-hold", title: "Accent Menu on Press and Hold", section: "input", domain: "-g", key: "ApplePressAndHoldEnabled",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: true)),
        MacSetting(id: "fn-keys", title: "Use F1, F2… as Function Keys", section: "input", domain: "-g", key: "com.apple.keyboard.fnState",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: false), needsLogout: true),
        MacSetting(id: "natural-scroll", title: "Natural Scrolling", section: "input", domain: "-g", key: "com.apple.swipescrolldirection",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: true), needsLogout: true),
        MacSetting(id: "tap-click", title: "Tap to Click", section: "input", domain: "com.apple.AppleMultitouchTrackpad", key: "Clicking",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: false), needsLogout: true,
                   alsoDomains: ["com.apple.driver.AppleBluetoothMultitouch.trackpad"]),

        // Screenshots
        MacSetting(id: "shot-location", title: "Save Screenshots To", section: "screenshots", domain: "com.apple.screencapture", key: "location",
                   kind: .choice([("Desktop", home("Desktop")), ("Downloads", home("Downloads")), ("Pictures", home("Pictures")),
                                  ("Documents", home("Documents"))], defaultIndex: 0), restart: "SystemUIServer"),
        MacSetting(id: "shot-format", title: "Screenshot Format", section: "screenshots", domain: "com.apple.screencapture", key: "type",
                   kind: .choice([("PNG", "png" as CFString), ("JPEG", "jpg" as CFString), ("HEIC", "heic" as CFString), ("PDF", "pdf" as CFString)], defaultIndex: 0),
                   restart: "SystemUIServer"),
        MacSetting(id: "shot-shadow", title: "Window Shadow in Screenshots", section: "screenshots", domain: "com.apple.screencapture", key: "disable-shadow",
                   kind: .toggle(on: false as CFBoolean, off: true as CFBoolean, defaultOn: true), restart: "SystemUIServer"),
        MacSetting(id: "shot-thumbnail", title: "Show Floating Thumbnail", section: "screenshots", domain: "com.apple.screencapture", key: "show-thumbnail",
                   kind: .toggle(on: true as CFBoolean, off: false as CFBoolean, defaultOn: true), restart: "SystemUIServer"),

        // Appearance
        MacSetting(id: "accent", title: "Accent Colour", section: "appearance", domain: "-g", key: "AppleAccentColor",
                   kind: .choice([("Multicolour", nil), ("Blue", 4 as CFNumber), ("Purple", 5 as CFNumber), ("Pink", 6 as CFNumber),
                                  ("Red", 0 as CFNumber), ("Orange", 1 as CFNumber), ("Yellow", 2 as CFNumber), ("Green", 3 as CFNumber),
                                  ("Graphite", -1 as CFNumber)], defaultIndex: 0),
                   notify: "AppleColorPreferencesChangedNotification"),
        MacSetting(id: "scrollbars", title: "Show Scroll Bars", section: "appearance", domain: "-g", key: "AppleShowScrollBars",
                   kind: .choice([("Automatically", "Automatic" as CFString), ("When Scrolling", "WhenScrolling" as CFString), ("Always", "Always" as CFString)], defaultIndex: 0),
                   notify: "AppleShowScrollBarsSettingChanged"),
    ]

    static func setting(_ id: String) -> MacSetting? { all.first { $0.id == id } }

    static let labels: [String: String] = [
        "dock-autohide": "Auto-Hide Dock", "dock-size": "Size", "dock-magnify": "Magnification", "dock-position": "Position",
        "dock-minimize": "Minimize", "dock-recents": "Recent Apps", "menubar-autohide": "Auto-Hide Menu Bar",
        "desktop-icons": "Desktop Icons", "hidden-files": "Hidden Files", "extensions": "File Extensions", "pathbar": "Path Bar",
        "statusbar": "Status Bar", "folders-first": "Folders on Top", "click-desktop": "Click Wallpaper", "mru-spaces": "Reorder Spaces",
        "group-apps": "Group by App", "separate-spaces": "Separate Spaces", "corner-tl": "Top Left", "corner-tr": "Top Right",
        "corner-bl": "Bottom Left", "corner-br": "Bottom Right", "key-repeat": "Key Repeat", "repeat-delay": "Repeat Delay",
        "press-hold": "Accent Menu", "fn-keys": "Standard F-Keys", "natural-scroll": "Natural Scroll", "tap-click": "Tap to Click",
        "shot-location": "Save To", "shot-format": "Format", "shot-shadow": "Window Shadow", "shot-thumbnail": "Thumbnail",
        "accent": "Accent", "scrollbars": "Scroll Bars",
    ]

    // MARK: Menus

    static let sections: [(id: String, title: String, icon: String)] = [
        ("dock", "Dock & Menu Bar", "sf:dock.rectangle"),
        ("finder", "Finder & Desktop", "sf:macwindow.on.rectangle"),
        ("spaces", "Mission Control", "sf:rectangle.3.group"),
        ("corners", "Hot Corners", "sf:rectangle.inset.topright.filled"),
        ("input", "Keyboard & Trackpad", "sf:keyboard"),
        ("screenshots", "Screenshots", "sf:camera.viewfinder"),
    ]

    static func items(section: String, settings app: AppSettings) -> [MenuItem] {
        all.filter { $0.section == section }.map { item(for: $0, app: app) }
    }

    static func item(for s: MacSetting, app: AppSettings) -> MenuItem {
        let suffix = s.needsLogout ? " (after log out)" : ""
        if let who = s.managedBy?(app) {
            return MenuItem(id: "mac:" + s.id, name: s.label, icon: "sf:lock.fill", description: "\(s.title): \(who). Change it in AINCRAD Settings › General.")
        }
        switch s.kind {
        case .toggle:
            let on = isOn(s)
            return MenuItem(id: "mac:" + s.id, name: s.label, icon: on ? "sf:checkmark.circle.fill" : "sf:circle",
                            action: .builtin("macset:toggle:" + s.id),
                            description: "\(s.title) is \(on ? "on. Choose to turn it off." : "off. Choose to turn it on.")" + suffix)
        case .choice(let options, _):
            let current = choiceIndex(s)
            return MenuItem(id: "mac:" + s.id, name: "\(s.label): \(options[current].label)", icon: "sf:list.bullet",
                            provider: "macsettings:choice:" + s.id, description: "\(s.title): \(options[current].label)." + suffix)
        }
    }

    static func choiceItems(_ id: String) -> [MenuItem] {
        guard let s = setting(id), case .choice(let options, _) = s.kind else { return [] }
        let current = choiceIndex(s)
        return options.enumerated().map { i, o in
            MenuItem(id: "mac:\(id):\(i)", name: o.label, icon: i == current ? "sf:checkmark.circle.fill" : "sf:circle",
                     action: .builtin("macset:choose:\(id):\(i)"))
        }
    }

    /// "macset:toggle:<id>" / "macset:choose:<id>:<index>".
    static func perform(_ builtin: String) -> String? {
        let parts = builtin.split(separator: ":").map(String.init)
        guard parts.count >= 3, let s = setting(parts[2]) else { return nil }
        switch (parts[1], s.kind) {
        case ("toggle", .toggle(let on, let off, _)):
            let next = !isOn(s)
            write(s, next ? on : off)
            return "\(s.title): \(next ? "on" : "off")" + (s.needsLogout ? ". Takes effect after you log out." : "")
        case ("choose", .choice(let options, _)):
            guard parts.count >= 4, let i = Int(parts[3]), options.indices.contains(i) else { return nil }
            write(s, options[i].value)
            return "\(s.title): \(options[i].label)" + (s.needsLogout ? ". Takes effect after you log out." : "")
        default: return nil
        }
    }

    // MARK: Every System Settings page

    static let pages: [(String, String, String)] = [
        ("Wi-Fi", "sf:wifi", "com.apple.wifi-settings-extension"), ("Bluetooth", "sf:dot.radiowaves.left.and.right", "com.apple.BluetoothSettings"),
        ("Network", "sf:network", "com.apple.Network-Settings.extension"), ("Notifications", "sf:bell.badge.fill", "com.apple.Notifications-Settings.extension"),
        ("Sound", "sf:speaker.wave.2.fill", "com.apple.Sound-Settings.extension"), ("Focus", "sf:moon.fill", "com.apple.Focus-Settings.extension"),
        ("Screen Time", "sf:hourglass", "com.apple.Screen-Time-Settings.extension"), ("General", "sf:gearshape", "com.apple.systempreferences.GeneralSettings"),
        ("About This Mac", "sf:info.circle", "com.apple.SystemProfiler.AboutExtension"), ("Software Update", "sf:arrow.triangle.2.circlepath", "com.apple.Software-Update-Settings.extension"),
        ("Storage", "sf:internaldrive.fill", "com.apple.settings.Storage"), ("AirDrop & Handoff", "sf:airplayaudio", "com.apple.AirDrop-Handoff-Settings.extension"),
        ("Login Items", "sf:person.badge.key.fill", "com.apple.LoginItems-Settings.extension"), ("Language & Region", "sf:globe", "com.apple.Localization-Settings.extension"),
        ("Date & Time", "sf:clock", "com.apple.Date-Time-Settings.extension"), ("Sharing", "sf:square.and.arrow.up", "com.apple.Sharing-Settings.extension"),
        ("Time Machine", "sf:clock.arrow.circlepath", "com.apple.Time-Machine-Settings.extension"), ("Startup Disk", "sf:externaldrive", "com.apple.Startup-Disk-Settings.extension"),
        ("Appearance", "sf:circle.lefthalf.filled", "com.apple.Appearance-Settings.extension"), ("Accessibility", "sf:accessibility", "com.apple.Accessibility-Settings.extension"),
        ("Control Center", "sf:switch.2", "com.apple.ControlCenter-Settings.extension"), ("Siri & Spotlight", "sf:magnifyingglass", "com.apple.Siri-Settings.extension"),
        ("Privacy & Security", "sf:hand.raised.fill", "com.apple.settings.PrivacySecurity.extension"), ("Desktop & Dock", "sf:dock.rectangle", "com.apple.Desktop-Settings.extension"),
        ("Displays", "sf:display.2", "com.apple.Displays-Settings.extension"), ("Wallpaper", "sf:photo.fill", "com.apple.Wallpaper-Settings.extension"),
        ("Screen Saver", "sf:sparkles.tv", "com.apple.ScreenSaver-Settings.extension"), ("Energy", "sf:bolt.fill", "com.apple.Energy-Settings.extension"),
        ("Lock Screen", "sf:lock.fill", "com.apple.Lock-Screen-Settings.extension"), ("Login Password", "sf:key.fill", "com.apple.Touch-ID-Settings.extension"),
        ("Users & Groups", "sf:person.2.fill", "com.apple.Users-Groups-Settings.extension"), ("Passwords", "sf:key.horizontal.fill", "com.apple.Passwords-Settings.extension"),
        ("Internet Accounts", "sf:at", "com.apple.Internet-Accounts-Settings.extension"), ("Game Center", "sf:gamecontroller.fill", "com.apple.Game-Center-Settings.extension"),
        ("Keyboard", "sf:keyboard.fill", "com.apple.Keyboard-Settings.extension"), ("Mouse", "sf:computermouse.fill", "com.apple.Mouse-Settings.extension"),
        ("Trackpad", "sf:rectangle.and.hand.point.up.left.fill", "com.apple.Trackpad-Settings.extension"), ("Game Controllers", "sf:gamecontroller", "com.apple.Game-Controller-Settings.extension"),
        ("Printers & Scanners", "sf:printer.fill", "com.apple.Print-Scan-Settings.extension"),
    ]

    static func pageItems() -> [MenuItem] {
        pages.map { name, icon, pane in
            MenuItem(id: "page:" + pane, name: name, icon: icon, action: .builtin("system:settings:" + pane), description: "Opens System Settings › \(name).")
        }
    }
}
