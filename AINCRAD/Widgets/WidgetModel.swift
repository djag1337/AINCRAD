import Foundation

/// One desktop widget. Position is in points from the top-left of its display.
struct WidgetConfig: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    /// clock, stat, hpbar, text, image, app, launcher
    var type: String
    /// Display name as shown in System Settings › Displays; "" = the main display.
    var display = ""
    var x = 100.0
    var y = 100.0
    var width = 240.0
    var height = 90.0
    var rotation = 0.0
    var opacity = 1.0
    var z = 0
    var locked = false
    var hidden = false
    /// Part of the HUD: shown only while the launcher is open (on that display), above it.
    var hud = false
    var style = WidgetStyle()
    /// Type-specific settings, kept as strings so new widget types need no schema change.
    var props: [String: String] = [:]

    var isInteractive: Bool { type == "app" || type == "launcher" || type == "gameshelf" }

    func prop(_ key: String, _ fallback: String) -> String { props[key].flatMap { $0.isEmpty ? nil : $0 } ?? fallback }
    func flag(_ key: String, _ fallback: Bool) -> Bool { props[key].map { $0 == "true" } ?? fallback }
}

extension WidgetConfig {
    private enum CodingKeys: String, CodingKey {
        case id, type, display, x, y, width, height, rotation, opacity, z, locked, hidden, hud, style, props
    }

    // Tolerant: a hand-written widget only needs "type".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WidgetConfig(type: try c.decode(String.self, forKey: .type))
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? d.id
        type = d.type
        display = try c.decodeIfPresent(String.self, forKey: .display) ?? d.display
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? d.x
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? d.y
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? d.width
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? d.height
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? d.rotation
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        z = try c.decodeIfPresent(Int.self, forKey: .z) ?? d.z
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? d.locked
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? d.hidden
        hud = try c.decodeIfPresent(Bool.self, forKey: .hud) ?? d.hud
        style = try c.decodeIfPresent(WidgetStyle.self, forKey: .style) ?? d.style
        props = try c.decodeIfPresent([String: String].self, forKey: .props) ?? d.props
    }
}

/// Visual overrides; nil means "use the active theme" (or the display's accent for `accent`).
struct WidgetStyle: Codable, Equatable {
    var font: String? = nil
    var fontSize = 18.0
    var textColor: String? = nil
    var accent: String? = nil
    var background: String? = nil
    var showPanel = true
    var shadow = true
}

struct WidgetLayout: Codable, Equatable {
    var schemaVersion = 1
    var widgets: [WidgetConfig] = []
}

extension WidgetLayout {
    private enum CodingKeys: String, CodingKey { case schemaVersion, widgets }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        widgets = try c.decodeIfPresent([WidgetConfig].self, forKey: .widgets) ?? []
    }
}

enum WidgetCatalog {
    /// A first HUD layout for a display of the given size: a big clock on the left edge and system
    /// gauges down the right, inside the HUD's brackets, clear of the top bar, the dock and the
    /// top-left corner (where SAO messages pop up).
    static func hudStarter(display: String, size: CGSize) -> [WidgetConfig] {
        func w(_ type: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double, _ props: [String: String],
               style: WidgetStyle = WidgetStyle()) -> WidgetConfig {
            WidgetConfig(type: type, display: display, x: x, y: y, width: width, height: height, opacity: 0.92, hud: true,
                         style: style, props: props)
        }
        let right = Double(size.width) - 60 - 260, mid = Double(size.height) / 2
        return [
            w("clock", 60, mid - 60, 300, 120, ["format": "HH:mm", "date": "EEEE, MMMM d"], style: WidgetStyle(fontSize: 22)),
            w("stat", right, mid - 130, 260, 70, ["source": "cpu", "show": "bar"]),
            w("stat", right, mid - 40, 260, 70, ["source": "memory", "show": "bar"]),
            w("stat", right, mid + 50, 260, 70, ["source": "disk", "show": "bar"]),
            w("stat", 60, Double(size.height) - 230, 260, 70, ["source": "network", "show": "text"]),
        ] + [hudQuestLog(display: display, size: size)]
    }

    /// The quest log's place in the HUD: the left edge, between the message corner and the clock.
    static func hudQuestLog(display: String, size: CGSize) -> WidgetConfig {
        WidgetConfig(type: "quests", display: display, x: 60, y: 205, width: 360, height: Double(size.height) / 2 - 60 - 205 - 12,
                     opacity: 0.92, hud: true, style: WidgetStyle(fontSize: 17), props: ["events": "true", "reminders": "true"])
    }

    struct Entry { let type: String; let name: String; let symbol: String; let make: () -> WidgetConfig }

    static let entries: [Entry] = [
        Entry(type: "clock", name: "Clock & date", symbol: "clock") {
            WidgetConfig(type: "clock", width: 260, height: 110, props: ["format": "HH:mm", "date": "EEEE, MMMM d"])
        },
        Entry(type: "hpbar", name: "HP bars (SAO)", symbol: "heart.text.square") {
            WidgetConfig(type: "hpbar", width: 380, height: 150,
                         props: ["rows": "Kirito:cpu, Asuna:memory, Silica:disk", "level": "uptime"])
        },
        Entry(type: "stat", name: "CPU", symbol: "cpu") {
            WidgetConfig(type: "stat", width: 240, height: 70, props: ["source": "cpu", "show": "bar"])
        },
        Entry(type: "stat", name: "Memory", symbol: "memorychip") {
            WidgetConfig(type: "stat", width: 240, height: 70, props: ["source": "memory", "show": "bar"])
        },
        Entry(type: "stat", name: "Disk", symbol: "internaldrive") {
            WidgetConfig(type: "stat", width: 240, height: 70, props: ["source": "disk", "show": "bar"])
        },
        Entry(type: "stat", name: "Battery / power", symbol: "battery.75percent") {
            WidgetConfig(type: "stat", width: 240, height: 70, props: ["source": "battery", "show": "bar"])
        },
        Entry(type: "stat", name: "Network", symbol: "network") {
            WidgetConfig(type: "stat", width: 260, height: 70, props: ["source": "network", "show": "text"])
        },
        Entry(type: "gameshelf", name: "Game shelf", symbol: "gamecontroller") {
            WidgetConfig(type: "gameshelf", width: 560, height: 190, style: WidgetStyle(fontSize: 12),
                         props: ["source": "all", "titles": "true"])
        },
        Entry(type: "quests", name: "Quest log (calendar & reminders)", symbol: "list.star") {
            WidgetConfig(type: "quests", width: 360, height: 270, style: WidgetStyle(fontSize: 17), props: ["events": "true", "reminders": "true"])
        },
        Entry(type: "party", name: "Party (busiest apps)", symbol: "person.3.fill") {
            WidgetConfig(type: "party", width: 320, height: 190, style: WidgetStyle(fontSize: 17), props: ["count": "3"])
        },
        Entry(type: "status", name: "Status effects", symbol: "sparkles") {
            WidgetConfig(type: "status", width: 360, height: 120, style: WidgetStyle(fontSize: 17))
        },
        Entry(type: "battlelog", name: "Battle log", symbol: "list.bullet.rectangle") {
            WidgetConfig(type: "battlelog", width: 340, height: 220, style: WidgetStyle(fontSize: 17))
        },
        Entry(type: "exp", name: "EXP bar", symbol: "star.circle") {
            WidgetConfig(type: "exp", width: 360, height: 80, style: WidgetStyle(fontSize: 17))
        },
        Entry(type: "text", name: "Text", symbol: "textformat") {
            WidgetConfig(type: "text", width: 300, height: 80, props: ["text": "Welcome to Sword Art Online!", "align": "center"])
        },
        Entry(type: "image", name: "Image", symbol: "photo") {
            WidgetConfig(type: "image", width: 200, height: 200, style: WidgetStyle(showPanel: false), props: ["path": "", "fit": "fit"])
        },
        Entry(type: "app", name: "App shortcut", symbol: "app.badge") {
            WidgetConfig(type: "app", width: 96, height: 104, style: WidgetStyle(fontSize: 14),
                         props: ["target": "com.apple.finder", "label": "true"])
        },
        Entry(type: "launcher", name: "Launcher button", symbol: "circle.circle") {
            WidgetConfig(type: "launcher", width: 90, height: 104, style: WidgetStyle(fontSize: 14, showPanel: false),
                         props: ["label": "Menu"])
        },
    ]
}

extension WidgetStyle {
    private enum CodingKeys: String, CodingKey { case font, fontSize, textColor, accent, background, showPanel, shadow }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WidgetStyle()
        font = try c.decodeIfPresent(String.self, forKey: .font)
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        textColor = try c.decodeIfPresent(String.self, forKey: .textColor)
        accent = try c.decodeIfPresent(String.self, forKey: .accent)
        background = try c.decodeIfPresent(String.self, forKey: .background)
        showPanel = try c.decodeIfPresent(Bool.self, forKey: .showPanel) ?? d.showPanel
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? d.shadow
    }
}
