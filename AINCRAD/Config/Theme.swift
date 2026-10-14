import AppKit

/// Font lookup shared by every surface, so a theme's two fonts are used consistently.
enum ThemeFonts {
    /// Prefers a semibold face (Rajdhani and DIN read best there), falling back to the system font.
    static func make(_ family: String, _ size: CGFloat) -> NSFont {
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 8, size: size)
            ?? NSFont(name: family, size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    static func body(_ theme: Theme, _ size: CGFloat) -> NSFont { make(theme.font.family, size) }

    static func display(_ theme: Theme, _ size: CGFloat) -> NSFont {
        make(theme.font.display.isEmpty ? theme.font.family : theme.font.display, size)
    }
}

/// Every visual property the launcher reads. Nothing about the SAO look lives in the renderer.
struct Theme: Codable, Equatable {
    var schemaVersion = 1
    var name = "Aincrad Classic"
    var colors = Colors()
    var font = Font()
    var geometry = Geometry()
    var effects = Effects()
    var animation = Animation()
    var sounds = Sounds()

    struct Colors: Codable, Equatable {
        var backdrop = "#00000000"
        var panel = "#F7F7F8F2"
        var panelText = "#43474E"
        var panelBorder = "#FFFFFFE6"
        var hover = "#FFFFFFFF"
        var accent = "#F5A623"
        var accentText = "#FFFFFF"
        var iconBadge = "#5D6169"
        var iconGlyph = "#FFFFFF"
        var circle = "#F8F8F9F2"
        var circleIcon = "#8E9299"
        var circleBorder = "#FFFFFF"
        var caption = "#FFFFFF"
        var captionShadow = "#000000CC"
        var shadow = "#0000005C"
        var infoFooter = "#E6E7EAF5"
        var infoIcon = "#9095A0"
    }

    struct Font: Codable, Equatable {
        /// Body text: menu rows, descriptions, widget text.
        var family = "Rajdhani"
        var size = 20.0
        var captionSize = 22.0
        /// Titles and chrome: top bar, HUD, info titles, message headers. "" = same as `family`.
        var display = "Orbitron"
    }

    struct Geometry: Codable, Equatable {
        var circleDiameter = 54.0
        var circleSpacing = 16.0
        var itemWidth = 212.0
        var itemHeight = 38.0
        var itemSpacing = 5.0
        var columnGap = 20.0
        var cornerRadius = 4.0
        /// Rows shown on each side of the focused row; further rows fade out.
        var visibleRows = 6
        var screenMargin = 40.0
        var infoPanelWidth = 230.0
        var infoPanelHeight = 340.0
        var infoPanelGap = 26.0
        /// Where the menu appears relative to the pointer, so the pointer isn't on a button when it opens.
        var cursorOffsetX = 72.0
        var cursorOffsetY = 0.0
        /// Corner radius of the info bubble.
        var bubbleRadius = 9.0
    }

    struct Effects: Codable, Equatable {
        var borderWidth = 1.0
        var shadowRadius = 10.0
        var shadowOpacity = 0.35
        var selectedRingWidth = 2.0
        /// Accent-coloured glow around the selected button/row; 0 disables.
        var selectedGlow = 12.0
        var glowOpacity = 0.65
        /// Degrees the columns and info panel turn away from the viewer; 0 = flat.
        var tilt = 0.0
        var showInfoPanel = true
        /// SAO heads-up frame (corner brackets, player bar, clock) around the screen while open.
        var hud = true
        /// Top-to-bottom shading of panels and buttons (0 = flat); gives the frosted-glass look.
        var gradient = 0.07
        /// Opacity of the thin highlight along the top edge of panels.
        var shine = 0.7
    }

    struct Animation: Codable, Equatable {
        /// classic, snappy, gentle or minimal: the base the other values override.
        var preset = "classic"
        var speed = 1.0
        var open = 0.30
        var stagger = 0.045
        var column = 0.22
        var rowStagger = 0.018
        var move = 0.20
        var highlight = 0.10
        var close = 0.14
        var dropDistance = 30.0
        var slideDistance = 18.0

        static func preset(_ name: String) -> Animation {
            var a = Animation()
            a.preset = name
            switch name {
            case "snappy":
                a.open = 0.18; a.stagger = 0.025; a.column = 0.13; a.rowStagger = 0.008
                a.move = 0.12; a.highlight = 0.06; a.close = 0.09; a.dropDistance = 18; a.slideDistance = 10
            case "gentle":
                a.open = 0.45; a.stagger = 0.07; a.column = 0.32; a.rowStagger = 0.03
                a.move = 0.28; a.highlight = 0.14; a.close = 0.2; a.dropDistance = 40; a.slideDistance = 26
            case "minimal":
                a.open = 0.15; a.stagger = 0; a.column = 0.12; a.rowStagger = 0
                a.move = 0.12; a.highlight = 0.06; a.close = 0.1; a.dropDistance = 0; a.slideDistance = 0
            default:
                a.preset = "classic"
            }
            return a
        }
    }

    /// "builtin:<name>" for the bundled sounds, a file path for your own, or "" for silence.
    struct Sounds: Codable, Equatable {
        var volume = 0.35
        var open = "builtin:open"
        var select = "builtin:select"
        var back = "builtin:back"
        var close = "builtin:close"
        var hover = ""
        var error = "builtin:error"
    }
}

extension Theme {
    static let classic = Theme()

    static let dark: Theme = {
        var t = Theme()
        t.name = "Dark Aincrad"
        t.colors.panel = "#24272DE8"
        t.colors.panelText = "#E4E6EA"
        t.colors.panelBorder = "#FFFFFF33"
        t.colors.hover = "#3A3E46F2"
        t.colors.iconBadge = "#E4E6EA"
        t.colors.iconGlyph = "#24272D"
        t.colors.circle = "#2A2D33E6"
        t.colors.circleIcon = "#C8CBD1"
        t.colors.circleBorder = "#FFFFFF40"
        t.colors.infoFooter = "#1B1D22F0"
        t.effects.shine = 0.12
        t.colors.infoIcon = "#C8CBD1"
        return t
    }()

    /// For macOS "Increase contrast": opaque panels, solid borders, no screen tint.
    func highContrast() -> Theme {
        var t = self
        func opaque(_ hex: String) -> String { NSColor(hex: hex).map { $0.withAlphaComponent(1).hexString } ?? hex }
        t.colors.panel = opaque(colors.panel)
        t.colors.hover = opaque(colors.hover)
        t.colors.circle = opaque(colors.circle)
        t.colors.infoFooter = opaque(colors.infoFooter)
        t.colors.panelBorder = colors.panelText
        t.colors.circleBorder = colors.panelText
        t.colors.backdrop = "#00000000"
        t.effects.borderWidth = max(effects.borderWidth, 1.5)
        return t
    }

    static let presets: [(id: String, theme: Theme)] = [("aincrad-classic", classic), ("aincrad-dark", dark)]
}
