import AppKit

/// Named snapshots of your setup — Dock, desktop icons, accent, appearance, volume, output,
/// keep-awake, AINCRAD theme and widgets — switched with one click. Saved in profiles.json.
struct Profile: Codable, Equatable {
    /// A preference value as JSON (bools, numbers and strings; nil = macOS default).
    enum Value: Codable, Equatable {
        case bool(Bool), int(Int), double(Double), string(String), none

        init(_ v: CFPropertyList?) {
            guard let v else { self = .none; return }
            if CFGetTypeID(v) == CFBooleanGetTypeID() { self = .bool((v as! NSNumber).boolValue) }
            else if let n = v as? NSNumber { self = CFNumberIsFloatType(n) ? .double(n.doubleValue) : .int(n.intValue) }
            else if let s = v as? String { self = .string(s) }
            else { self = .none }
        }

        var plist: CFPropertyList? {
            switch self {
            case .bool(let b): return b as CFBoolean
            case .int(let i): return i as CFNumber
            case .double(let d): return d as CFNumber
            case .string(let s): return s as CFString
            case .none: return nil
            }
        }
    }

    var name: String
    var mac: [String: Value] = [:]
    var dark: Bool?
    var volume: Float?
    var output: String?
    var keepAwake: Bool?
    var theme: String?
    var widgets: Bool?
}

enum Profiles {
    /// The Mac settings a profile remembers (the ones that change how the desktop looks and feels).
    static let captured = ["dock-autohide", "dock-size", "dock-magnify", "dock-position", "desktop-icons", "accent", "menubar-autohide", "dock-recents"]

    private static var url: URL { ConfigStore.baseDirectory.appendingPathComponent("profiles.json") }

    static func load() -> [Profile] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Profile].self, from: $0) } ?? []
    }

    private static func save(_ list: [Profile]) {
        try? JSONEncoder().encode(list).write(to: url, options: .atomic)
    }

    static func current(named name: String, app: AppSettings) -> Profile {
        var p = Profile(name: name)
        for id in captured {
            guard let s = MacSettings.setting(id), s.managedBy?(app) == nil else { continue }
            p.mac[id] = Profile.Value(MacSettings.read(s))
        }
        p.dark = SystemControls.isDark
        p.volume = SystemControls.volume()
        let out = SystemControls.defaultDevice(output: true)
        p.output = SystemControls.audioDevices().first { $0.id == out }?.name
        p.keepAwake = SystemControls.keepingAwake
        p.theme = app.theme
        p.widgets = app.widgetsEnabled
        return p
    }

    static func saveCurrent(named name: String, app: AppSettings) {
        var list = load().filter { $0.name != name }
        list.append(current(named: name, app: app))
        save(list)
        Log.info("profiles: saved \(name)")
    }

    static func delete(_ name: String) {
        save(load().filter { $0.name != name })
    }

    /// Applies a profile; `theme` and `widgets` are AINCRAD's own (switched through the app).
    static func apply(_ p: Profile, app: AppSettings, theme: (String) -> Void, widgets: (Bool) -> Void) {
        var restarts = Set<String>()
        for (id, value) in p.mac {
            guard let s = MacSettings.setting(id), s.managedBy?(app) == nil,
                  Profile.Value(MacSettings.read(s)) != value else { continue }
            MacSettings.write(s, value.plist, restartNow: false)
            if let r = s.restart { restarts.insert(r) }
        }
        restarts.forEach(MacSettings.restart)   // once each, after every change is written
        if let d = p.dark, d != SystemControls.isDark { SystemControls.setDark(d) }
        if let name = p.output, let device = SystemControls.audioDevices().first(where: { $0.name == name && $0.hasOutput }) {
            SystemControls.setDefaultDevice(device.id, output: true)
        }
        if let v = p.volume { SystemControls.setVolume(v) }
        if let k = p.keepAwake { SystemControls.setKeepAwake(k) }
        if let t = p.theme, t != app.theme { theme(t) }
        if let w = p.widgets, w != app.widgetsEnabled { widgets(w) }
        Log.info("profiles: applied \(p.name)")
    }

    static func menuItems() -> [MenuItem] {
        var out = [MenuItem(id: "profiles:save", name: "Save Current Setup as Profile…", icon: "sf:plus.circle.fill", action: .builtin("profiles:save"),
                            description: "Remembers your Dock, desktop icons, accent, appearance, volume, output, keep-awake, AINCRAD theme and widgets.")]
        for p in load() {
            out.append(MenuItem(id: "profile:" + p.name, name: p.name, icon: "sf:person.crop.rectangle.stack.fill", children: [
                MenuItem(id: "profile-apply:" + p.name, name: "Switch to \(p.name)", icon: "sf:arrow.right.circle.fill",
                         action: .builtin("profiles:apply:" + (p.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? p.name))),
                MenuItem(id: "profile-update:" + p.name, name: "Update with Current Setup", icon: "sf:arrow.triangle.2.circlepath",
                         action: .builtin("profiles:update:" + (p.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? p.name))),
                MenuItem(id: "profile-delete:" + p.name, name: "Delete Profile", icon: "sf:trash",
                         action: .builtin("profiles:delete:" + (p.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? p.name))),
            ]))
        }
        return out
    }
}
