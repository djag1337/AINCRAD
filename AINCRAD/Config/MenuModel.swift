import Foundation

enum MenuAction: Codable, Equatable {
    case app(String)      // .app path or bundle identifier
    case open(String)     // file or folder, opened with its default application
    case url(String)
    case builtin(String)  // reload, openConfig, openLog, pause, quit, settings
    case shortcut(String) // a shortcut from the Shortcuts app, by name
    case shell(String)    // zsh command line; only runs when settings.allowShellCommands is true

    private enum CodingKeys: String, CodingKey { case type, target }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let target = try c.decode(String.self, forKey: .target)
        switch type {
        case "app": self = .app(target)
        case "open": self = .open(target)
        case "url": self = .url(target)
        case "builtin": self = .builtin(target)
        case "shortcut": self = .shortcut(target)
        case "shell": self = .shell(target)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown action type \"\(type)\"")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let (type, target) = parts
        try c.encode(type, forKey: .type)
        try c.encode(target, forKey: .target)
    }

    static let types = ["app", "open", "url", "shortcut", "shell", "builtin"]

    init?(type: String, target: String) {
        switch type {
        case "app": self = .app(target)
        case "open": self = .open(target)
        case "url": self = .url(target)
        case "builtin": self = .builtin(target)
        case "shortcut": self = .shortcut(target)
        case "shell": self = .shell(target)
        default: return nil
        }
    }

    var parts: (String, String) {
        switch self {
        case .app(let v): return ("app", v)
        case .open(let v): return ("open", v)
        case .url(let v): return ("url", v)
        case .builtin(let v): return ("builtin", v)
        case .shortcut(let v): return ("shortcut", v)
        case .shell(let v): return ("shell", v)
        }
    }
}

struct MenuItem: Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    /// "sf:<symbol>", "app:<path>", "file:<path>" or "image:<path>". Omitted = derived from the action.
    var icon: String? = nil
    var action: MenuAction? = nil
    var children: [MenuItem]? = nil
    /// Dynamic children filled at open time, e.g. "applications".
    var provider: String? = nil
    var accent: String? = nil
    var hidden: Bool? = nil
    /// Shown in the info panel instead of the derived description.
    var description: String? = nil
    /// Global shortcut that runs this item directly, e.g. "option+shift+1".
    var shortcut: String? = nil
    var visibleWhen: Conditions? = nil

    struct Conditions: Codable, Equatable {
        /// Only on the display with this name (as shown in System Settings › Displays).
        var display: String? = nil
        /// Bundle identifier that must be running / must not be running / must be installed.
        var appRunning: String? = nil
        var appNotRunning: String? = nil
        var appInstalled: String? = nil
    }

    var hasSubmenu: Bool { children != nil || provider != nil }
    var isVisible: Bool { hidden != true }
}

extension MenuItem {
    private enum CodingKeys: String, CodingKey {
        case id, name, icon, action, children, provider, accent, hidden, description, shortcut, visibleWhen
    }

    // Hand-written so a user-authored item doesn't need an id.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        action = try c.decodeIfPresent(MenuAction.self, forKey: .action)
        children = try c.decodeIfPresent([MenuItem].self, forKey: .children)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        accent = try c.decodeIfPresent(String.self, forKey: .accent)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        shortcut = try c.decodeIfPresent(String.self, forKey: .shortcut)
        visibleWhen = try c.decodeIfPresent(Conditions.self, forKey: .visibleWhen)
    }
}

struct MenuFile: Codable, Equatable {
    var schemaVersion = 1
    var root: [MenuItem]
}

extension MenuFile {
    private enum CodingKeys: String, CodingKey { case schemaVersion, root }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        root = try c.decode([MenuItem].self, forKey: .root)
    }
}
