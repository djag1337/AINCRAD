import AppKit

/// The SAO description panel left of the root buttons: title, large icon, and a footer that
/// describes whatever is focused or hovered.
final class InfoPanel {
    let layer = CALayer()
    private let title = CATextLayer()
    private let divider = CALayer()
    private let icon = CALayer()
    private let footer = CALayer()
    private let body = CATextLayer()
    private let pointer = CAShapeLayer()
    private var theme = Theme.classic
    private var scale: CGFloat = 1
    private var shownID: String?
    private var tailLength: CGFloat = 13

    init() {
        [title, divider, icon, footer, body].forEach(layer.addSublayer)
        layer.addSublayer(pointer)
        icon.contentsGravity = .resizeAspect
        body.isWrapped = true
        title.alignmentMode = .center
        title.truncationMode = .end
    }

    var size: CGSize { CGSize(width: theme.geometry.infoPanelWidth, height: theme.geometry.infoPanelHeight) }

    func configure(theme: Theme, titleFont: NSFont, bodyFont: NSFont, scale: CGFloat) {
        self.theme = theme
        self.scale = scale
        shownID = nil
        let c = theme.colors
        let W = size.width, H = size.height
        let footerTop = (H * 0.66).rounded()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.backgroundColor = themeColor(c.panel).cgColor
        let radius = theme.geometry.bubbleRadius
        layer.cornerRadius = radius
        layer.borderWidth = theme.effects.borderWidth
        layer.borderColor = themeColor(c.panelBorder).cgColor
        layer.shadowColor = themeColor(c.shadow).cgColor
        layer.shadowOpacity = Float(theme.effects.shadowOpacity)
        layer.shadowRadius = theme.effects.shadowRadius
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowPath = CGPath(roundedRect: layer.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)

        let titleH = ceil(titleFont.ascender - titleFont.descender)
        title.frame = CGRect(x: 14, y: 16, width: W - 28, height: titleH)
        title.font = titleFont
        title.fontSize = titleFont.pointSize
        title.foregroundColor = themeColor(c.panelText).cgColor
        title.contentsScale = scale
        divider.frame = CGRect(x: 18, y: title.frame.maxY + 8, width: W - 36, height: 1)
        divider.backgroundColor = themeColor(c.panelText).withAlphaComponent(0.4).cgColor

        let iconSize: CGFloat = min(84, footerTop - divider.frame.maxY - 30)
        icon.frame = CGRect(x: (W - iconSize) / 2, y: divider.frame.maxY + (footerTop - divider.frame.maxY - iconSize) / 2,
                            width: iconSize, height: iconSize)
        footer.frame = CGRect(x: 0, y: footerTop, width: W, height: H - footerTop)
        footer.backgroundColor = themeColor(c.infoFooter).cgColor
        footer.cornerRadius = radius
        // Round only the footer's bottom corners (flipped geometry: max Y is the bottom).
        footer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        body.frame = CGRect(x: 16, y: footerTop + 14, width: W - 32, height: H - footerTop - 22)
        body.font = bodyFont
        body.fontSize = bodyFont.pointSize
        body.foregroundColor = themeColor(c.panelText).cgColor
        body.contentsScale = scale

        // Bubble tail pointing at the chosen button.
        // Reaches across most of the gap, stopping just short of the button.
        tailLength = max(8, theme.geometry.infoPanelGap - 5)
        let L = tailLength
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -1, y: 0))
        path.addQuadCurve(to: CGPoint(x: L, y: 10), control: CGPoint(x: L * 0.45, y: 6.5))
        path.addQuadCurve(to: CGPoint(x: -1, y: 22), control: CGPoint(x: L * 0.45, y: 15.5))
        path.closeSubpath()
        pointer.path = path
        pointer.fillColor = themeColor(c.panel).cgColor
    }

    /// Places the panel so its right edge sits at `rightX`, centred on `centerY` but kept on
    /// screen, with the pointer aimed at `pointerY`.
    func place(rightX: CGFloat, centerY: CGFloat, pointerY: CGFloat, bounds: CGRect, margin: CGFloat) {
        let H = size.height
        let top = min(max(centerY - H / 2, bounds.minY + margin), bounds.maxY - margin - H)
        // Position, not frame: the panel may carry a tilt or bubble transform.
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.position = CGPoint(x: rightX - size.width / 2, y: top + H / 2)
        let py = min(max(pointerY - top, 18), H - 18)
        pointer.frame = CGRect(x: size.width, y: py - 11, width: tailLength, height: 22)
    }

    /// The tail tip relative to the panel's centre: the point the bubble grows from.
    var tailOffset: CGPoint {
        CGPoint(x: size.width / 2 + tailLength, y: pointer.frame.midY - size.height / 2)
    }

    func show(_ item: MenuItem, detail: String, iconSpec: String) {
        guard item.id != shownID else { return }
        shownID = item.id
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.12
        layer.add(fade, forKey: "content")
        title.string = item.name
        body.string = detail
        let side = icon.bounds.width
        icon.contents = IconCache.shared.image(iconSpec, size: side,
                                               tint: IconCache.isSymbol(iconSpec) ? themeColor(theme.colors.infoIcon) : nil,
                                               scale: scale)
    }

    static func detail(for item: MenuItem, childCount: Int?) -> String {
        let kind: String, line: String
        switch item.action {
        case .app(let t):
            kind = "Application"
            line = ActionRunner.appURL(t).map { tilde($0.path) } ?? "\(t) (not found)"
        case .open(let p):
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: (p as NSString).expandingTildeInPath, isDirectory: &isDir)
            kind = !exists ? "Missing" : isDir.boolValue ? "Folder" : "File"
            line = tilde((p as NSString).expandingTildeInPath)
        case .url(let u):
            kind = "Website"
            line = URL(string: u)?.host ?? u
        case .builtin(let b):
            kind = "AINCRAD"
            line = ["reload": "Reload configuration", "openConfig": "Show the menu file", "openLog": "Show the log",
                    "pause": "Pause activation", "quit": "Quit AINCRAD", "settings": "Open AINCRAD settings"][b] ?? b
        case .shortcut(let n):
            kind = "Shortcut"
            line = n
        case .shell(let c):
            kind = "Command"
            line = c
        case nil:
            if item.provider == "applications" { kind = "Menu"; line = "Every installed application" }
            else if item.provider == "appCategories" { kind = "Menu"; line = "Your apps, sorted into categories" }
            else if item.provider == "games" { kind = "Menu"; line = "Games from Steam, Heroic, Prism and your Applications" }
            else if item.provider == "recentApps" { kind = "Menu"; line = "Recently used applications" }
            else if item.hasSubmenu { kind = "Menu"; line = childCount.map { "\($0) item\($0 == 1 ? "" : "s")" } ?? "" }
            else { kind = "Empty"; line = "" }
        }
        let text = item.description ?? line
        var out = "[\(kind)]\n\(text)"
        if let s = item.shortcut { out += "\nShortcut: \(s)" }
        return out
    }

    private static func tilde(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
