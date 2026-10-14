import Foundation

struct HotKeySpec: Codable, Equatable {
    var key: String
    var modifiers: [String]
}

struct GestureSettings: Codable, Equatable {
    var enabled = false
    /// down, up, left, right, any, or none (open as soon as both buttons are held).
    var slide = "down"
    var distance = 40.0
    /// How long a right press waits for the left button before it is delivered as a normal right click.
    var chordWindowMs = 90.0
    var maxSlideMs = 1200.0
    var activationDelayMs = 0.0
    var disableInFullScreen = true
    /// Bundle identifiers where the gesture is ignored, e.g. games.
    var excludedApps: [String] = []
    /// "both": hold both buttons and slide. "right": hold the right button and slide (any mouse,
    /// including Magic Mouse).
    var buttons = "both"
    /// Finger swipe on a Magic Mouse (or trackpad) surface; needs no Accessibility permission.
    var touch = false
    var touchFingers = 2
    /// Fraction of the surface's height to travel.
    var touchDistance = 0.22
    /// "mouse" (Magic Mouse only) or "all" (trackpads too; they'd also scroll with two fingers).
    var touchDevices = "mouse"
}

struct AppSettings: Codable, Equatable {
    var schemaVersion = 1
    var hotKey = HotKeySpec(key: "`", modifiers: ["option"])
    var gesture = GestureSettings()
    /// cursor: at the pointer; gestureStart: where the mouse gesture began; center: centre of the active display.
    var placement = "cursor"
    /// File name (without .json) in the themes folder.
    var theme = "aincrad-classic"
    /// "system" follows macOS Reduce Motion; "on" / "off" override it.
    var reducedMotion = "system"
    var activationPaused = false
    var soundsEnabled = true
    /// Shell-command menu actions are refused unless this is on (protects imported menus).
    var allowShellCommands = false
    var launchAtLogin = false
    /// Opacity of the whole HUD widget layer (each widget's own opacity multiplies with it).
    var hudWidgetOpacity = 1.0
    /// The starter HUD widgets were added once; never re-add them after the user removes them.
    var hudStarterAdded = false
    /// The HUD quest log was added once (for layouts made before it existed).
    var hudQuestLogAdded = false
    var widgetsEnabled = true
    /// Accent colour per display name, e.g. {"Sceptre F22": "#3FA9F5", "Q27B13": "#E0303A"}.
    /// Applies to the launcher and widgets on that display unless they set their own.
    var displayAccents: [String: String] = [:]
    /// Per-extension approval: enabled flag plus the permissions the user agreed to.
    var extensions: [String: ExtensionApproval] = [:]
    /// Bundled plugins already copied into Extensions/ (id → version), so deleted ones stay deleted.
    var seededPlugins: [String: String] = [:]
    /// Where Browse reads its catalog: a folder path or an https URL to catalog.json.
    var catalogURL = AppSettings.communityCatalog
    /// Name in the HUD's player bar; empty = your first name.
    var playerName = ""
    /// Mirror macOS notifications as SAO bubbles (needs Accessibility).
    var notificationBubbles = false
    /// Close the grey macOS banner once the SAO bubble shows it.
    var notificationsHideOriginal = true
    var notificationSeconds = 6.0
    /// Your catalog repository (a clone of the GitHub repo) for the Publish buttons.
    var catalogRepoPath = "~/Documents/AINCRAD-catalog"
    /// Daily-use command layer: local clipboard, captures, workspaces and adaptive suggestions.
    var productivityEnabled = true
    var clipboardHistoryLimit = 100
    var commandDeckEnabled = true
    /// Optional desktop replacement panels. Apple UI hiding is independently reversible.
    var shellModeEnabled = true
    /// Hide Apple's Dock entirely (every app, every Space) while AINCRAD runs.
    var hideAppleDock = false
    /// Hide Apple's menu bar entirely (no slide-in at the top edge) while AINCRAD runs.
    var hideAppleMenuBar = false
    /// Retired ("while the launcher is open" hiding); kept so older settings files still decode.
    var shellHideMenuBar = false
    var shellHideDock = false
    /// Keep the SAO bar and dock on screen the whole time AINCRAD runs, in place of Apple's.
    var shellReplaceSystem = false
    /// With the above on: let the real menu bar show when the pointer reaches the top edge.
    var shellRevealMenus = false
    static let communityCatalog = "https://raw.githubusercontent.com/djag1337/AINCRAD-catalog/main/catalog.json"
}
