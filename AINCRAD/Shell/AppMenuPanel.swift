import AppKit

/// Reads menus through Accessibility (an app's menu bar, the menu bar icons) for the SAO panels.
enum AXMenus {
    /// A menu entry: either an Accessibility element (pressed when chosen) or AINCRAD's own item
    /// with fixed `kids` and a `run` action.
    struct Node {
        var title: String
        var enabled = true
        var shortcut = ""
        var checked = false
        var element: AXUIElement?
        var hasChildren = false
        var kids: [Node]?
        var run: (() -> Void)?
        var separator: Bool { title.isEmpty && !hasChildren }

        static func action(_ title: String, enabled: Bool = true, checked: Bool = false, _ run: @escaping () -> Void) -> Node {
            Node(title: title, enabled: enabled, checked: checked, run: run)
        }
        static func submenu(_ title: String, _ kids: [Node]) -> Node {
            Node(title: title, enabled: !kids.isEmpty, hasChildren: true, kids: kids)
        }
        static let separatorLine = Node(title: "")
    }

    /// The menu bar's titles (Apple, the app menu, File, Edit, …).
    static func top(_ pid: pid_t) -> [Node] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let bar: AXUIElement = attr(app, kAXMenuBarAttribute) else { return [] }
        return (attr(bar, kAXChildrenAttribute) as [AXUIElement]? ?? []).compactMap { item in
            let title: String = attr(item, kAXTitleAttribute) ?? ""
            guard !title.isEmpty else { return nil }
            return Node(title: title, enabled: attr(item, kAXEnabledAttribute) ?? true, shortcut: "", checked: false,
                        element: item, hasChildren: true)
        }
    }

    /// The items inside a menu bar title or a submenu item.
    static func children(_ node: Node) -> [Node] {
        if let kids = node.kids { return kids }
        guard let element = node.element, let menu = (attr(element, kAXChildrenAttribute) as [AXUIElement]?)?.first else { return [] }
        let items: [AXUIElement] = attr(menu, kAXChildrenAttribute) ?? []
        var out: [Node] = []
        for item in items {
            let title: String = attr(item, kAXTitleAttribute) ?? ""
            let sub = !(attr(item, kAXChildrenAttribute) as [AXUIElement]? ?? []).isEmpty
            let mark: String = attr(item, kAXMenuItemMarkCharAttribute) ?? ""
            let node = Node(title: title, enabled: attr(item, kAXEnabledAttribute) ?? false, shortcut: shortcut(item),
                            checked: !mark.isEmpty, element: item, hasChildren: sub)
            // No doubled or edge separators.
            if node.separator && (out.isEmpty || out.last?.separator == true) { continue }
            out.append(node)
        }
        while out.last?.separator == true { out.removeLast() }
        return out
    }

    static func press(_ node: Node) {
        if let run = node.run { return run() }
        if let element = node.element { AXUIElementPerformAction(element, kAXPressAction as CFString) }
    }

    /// The menu bar icons of every app (Wi-Fi, Sound, Bluetooth, third-party status items).
    /// Pressing one opens its menu, as clicking it in the menu bar would.
    static func extras() -> [Node] {
        var out: [Node] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != getpid() {
            let el = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(el, 0.25)
            guard let bar: AXUIElement = attr(el, "AXExtrasMenuBar") else { continue }
            for item in (attr(bar, kAXChildrenAttribute) as [AXUIElement]? ?? []) {
                let label = [attr(item, kAXTitleAttribute) as String?, attr(item, kAXDescriptionAttribute) as String?,
                             attr(item, kAXHelpAttribute) as String?].compactMap { $0 }.first { !$0.isEmpty }
                    ?? app.localizedName ?? "Item"
                out.append(Node(title: label, element: item))
            }
        }
        return out
    }

    private static func shortcut(_ item: AXUIElement) -> String {
        guard let char: String = attr(item, kAXMenuItemCmdCharAttribute), !char.isEmpty else { return "" }
        let mods: Int = attr(item, kAXMenuItemCmdModifiersAttribute) ?? 0
        var s = ""
        if mods & 4 != 0 { s += "⌃" }
        if mods & 2 != 0 { s += "⌥" }
        if mods & 1 != 0 { s += "⇧" }
        if mods & 8 == 0 { s += "⌘" }
        return s + char.uppercased()
    }

    private static func attr<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

/// An app's menus as SAO columns dropping from the top bar's player block: hover a title or a
/// submenu to open the next column, click an item to run it in that app.
final class AppMenuPanel {
    private var panel: NSPanel?
    private let view = AppMenuView()
    private(set) var isOpen = false

    func show(app: NSRunningApplication, anchor: NSRect, screen: NSScreen, theme: Theme, level: NSWindow.Level,
              onPick: @escaping (AXMenus.Node) -> Void) {
        let top = AXMenus.top(app.processIdentifier)
        guard !top.isEmpty else {
            Log.info("app menus: \(app.localizedName ?? "?") exposes no menu bar")
            return
        }
        show(top, title: (app.localizedName ?? "App") + "  ·  MENUS", anchor: anchor, screen: screen, theme: theme,
             level: level, rising: false, onPick: onPick)
    }

    /// `rising`: the first column opens upward from `anchor` (the dock); otherwise it drops down (the top bar).
    func show(_ nodes: [AXMenus.Node], title: String, anchor: NSRect, screen: NSScreen, theme: Theme, level: NSWindow.Level,
              rising: Bool, onPick: @escaping (AXMenus.Node) -> Void) {
        guard !nodes.isEmpty else { return }
        let p = panel ?? ShellPanel()
        p.level = NSWindow.Level(rawValue: level.rawValue + 1)
        // Explicit, so clicks on the panel's transparent parts land here (and dismiss the menu)
        // instead of falling through to the launcher, which would treat them as "back" and close.
        p.ignoresMouseEvents = false
        p.setFrame(screen.frame, display: false)
        p.contentView = view
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        // Anchor in the view's top-left coordinates.
        let a = CGRect(x: anchor.minX - screen.frame.minX, y: screen.frame.maxY - anchor.maxY, width: anchor.width, height: anchor.height)
        view.onPick = { [weak self] node in
            self?.hide()
            onPick(node)
        }
        view.onDismiss = { [weak self] in self?.hide() }
        view.present(top: nodes, title: title, anchor: a, rising: rising, theme: theme, scale: screen.backingScaleFactor)
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p
        isOpen = true
        SoundPlayer.shared.play(.open)
    }

    func hide() {
        guard isOpen else { return }
        isOpen = false
        panel?.orderOut(nil)
        view.clear()
    }
}

private final class AppMenuView: NSView {
    private final class Column {
        var nodes: [AXMenus.Node]
        let layer = CALayer()
        var rows: [CALayer] = []
        var frame = CGRect.zero
        var hovered: Int?
        var scroll: CGFloat = 0
        init(_ nodes: [AXMenus.Node]) { self.nodes = nodes }
    }

    private var columns: [Column] = []
    private var theme = Theme.classic
    private var scale: CGFloat = 2
    private var anchor = CGRect.zero
    private var rising = false
    private let header = CATextLayer()
    private var tracking: NSTrackingArea?
    var onPick: ((AXMenus.Node) -> Void)?
    var onDismiss: (() -> Void)?

    private let width: CGFloat = 250, rowH: CGFloat = 32, sepH: CGFloat = 9, gap: CGFloat = 8

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func present(top: [AXMenus.Node], title: String, anchor: CGRect, rising: Bool, theme: Theme, scale: CGFloat) {
        wantsLayer = true
        self.theme = theme
        self.scale = scale
        self.anchor = anchor
        self.rising = rising
        clear()
        let f = ThemeFonts.display(theme, 12)
        header.font = f
        header.fontSize = f.pointSize
        header.foregroundColor = themeColor(theme.colors.panelText).cgColor
        header.string = title.uppercased()
        header.contentsScale = scale
        header.alignmentMode = .left
        header.backgroundColor = themeColor(theme.colors.panel).withAlphaComponent(0.95).cgColor
        header.borderColor = themeColor(theme.colors.accent).cgColor
        header.borderWidth = 1
        header.cornerRadius = 4
        header.alignmentMode = .center
        layer?.addSublayer(header)
        addColumn(top, from: nil)
    }

    func clear() {
        columns.forEach { $0.layer.removeFromSuperlayer() }
        columns = []
        header.removeFromSuperlayer()
    }

    private func height(of nodes: [AXMenus.Node]) -> CGFloat {
        nodes.reduce(0) { $0 + ($1.separator ? sepH : rowH) } + 8
    }

    /// Opens a column for `nodes`; `from` is the row (column index, row frame in view coordinates) it hangs off.
    private func addColumn(_ nodes: [AXMenus.Node], from: (Int, CGRect)?) {
        let col = Column(nodes)
        // Columns stay between the top bar and the SAO dock; long ones scroll.
        let floor = rising ? anchor.minY - 14 : bounds.height - ShellController.dockHeight - 16
        let ceiling = rising ? 40 : anchor.maxY + 6
        let h = min(height(of: nodes), floor - ceiling)
        var x: CGFloat, y: CGFloat
        if let (level, row) = from {
            let parent = columns[level].frame
            x = parent.maxX + gap
            if x + width > bounds.width - 8 { x = parent.minX - gap - width }
            y = row.minY - 4
        } else if rising {
            // From the dock: rises above the button, under its name tag.
            x = anchor.midX - width / 2
            y = anchor.minY - 14 - h
        } else {
            // From the top bar: drops below the click, under its name tag.
            x = anchor.minX
            y = anchor.maxY + 34
        }
        x = min(max(x, 8), bounds.width - width - 8)
        y = min(max(y, ceiling), floor - h)
        col.frame = CGRect(x: x, y: y, width: width, height: h)
        if from == nil {
            let w = min(header.preferredFrameSize().width + 20, width)
            Motion.instant { header.frame = CGRect(x: x, y: rising ? y - 26 : anchor.maxY + 8, width: w, height: 20) }
        }
        let c = theme.colors
        Motion.instant {
            col.layer.frame = col.frame
            col.layer.backgroundColor = themeColor(c.panel).withAlphaComponent(0.97).cgColor
            col.layer.cornerRadius = 6
            col.layer.borderWidth = 1
            col.layer.borderColor = themeColor(c.panelBorder).cgColor
            col.layer.shadowColor = themeColor(c.shadow).cgColor
            col.layer.shadowOpacity = 0.5
            col.layer.shadowRadius = 10
            col.layer.shadowOffset = CGSize(width: 0, height: 3)
            col.layer.masksToBounds = false
            let clip = CALayer()
            clip.frame = col.layer.bounds
            clip.masksToBounds = true
            clip.cornerRadius = 6
            col.layer.addSublayer(clip)
            let accent = CALayer()
            accent.frame = CGRect(x: 0, y: 0, width: 3, height: col.frame.height)
            accent.backgroundColor = themeColor(c.accent).cgColor
            clip.addSublayer(accent)
            var ry: CGFloat = 4
            for node in nodes {
                let r = makeRow(node, y: ry)
                clip.addSublayer(r)
                col.rows.append(r)
                ry += node.separator ? sepH : rowH
            }
        }
        layer?.addSublayer(col.layer)
        columns.append(col)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.12
        col.layer.add(fade, forKey: "in")
    }

    private func makeRow(_ node: AXMenus.Node, y: CGFloat) -> CALayer {
        let c = theme.colors, text = themeColor(c.panelText)
        let row = CALayer()
        row.frame = CGRect(x: 3, y: y, width: width - 3, height: node.separator ? sepH : rowH)
        if node.separator {
            let line = CALayer()
            line.frame = CGRect(x: 12, y: sepH / 2, width: width - 30, height: 1)
            line.backgroundColor = text.withAlphaComponent(0.18).cgColor
            row.addSublayer(line)
            return row
        }
        let color = node.enabled ? text : text.withAlphaComponent(0.35)
        let body = ThemeFonts.body(theme, 16)
        func label(_ s: String, _ font: NSFont, _ frame: CGRect, _ align: CATextLayerAlignmentMode) -> CATextLayer {
            let t = CATextLayer()
            t.string = s
            t.font = font
            t.fontSize = font.pointSize
            t.foregroundColor = color.cgColor
            t.alignmentMode = align
            t.truncationMode = .end
            t.contentsScale = scale
            t.frame = frame
            t.name = "text"
            return t
        }
        let mid = rowH / 2
        if node.checked { row.addSublayer(label("✓", body, CGRect(x: 6, y: mid - 10, width: 14, height: 20), .center)) }
        let right = node.hasChildren ? "›" : node.shortcut
        let rightW: CGFloat = right.isEmpty ? 0 : (node.hasChildren ? 16 : 64)
        row.addSublayer(label(node.title, body, CGRect(x: 22, y: mid - 10, width: width - 40 - rightW, height: 21), .left))
        if !right.isEmpty {
            let f = node.hasChildren ? ThemeFonts.body(theme, 18) : ThemeFonts.body(theme, 13)
            row.addSublayer(label(right, f, CGRect(x: width - 16 - rightW, y: mid - (node.hasChildren ? 11 : 8), width: rightW, height: 22), .right))
        }
        return row
    }

    private func setHover(_ level: Int, _ index: Int?) {
        let col = columns[level]
        guard col.hovered != index else { return }
        let c = theme.colors
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        if let old = col.hovered { style(col.rows[old], node: col.nodes[old], on: false) }
        col.hovered = index
        if let index { style(col.rows[index], node: col.nodes[index], on: true) }
        CATransaction.commit()
        // Deeper columns belong to the old hover.
        while columns.count > level + 1 { columns.removeLast().layer.removeFromSuperlayer() }
        guard let index else { return }
        SoundPlayer.shared.play(.hover)
        let node = col.nodes[index]
        if node.hasChildren && node.enabled {
            let kids = AXMenus.children(node)
            if !kids.isEmpty {
                let r = col.rows[index].frame.offsetBy(dx: col.frame.minX, dy: col.frame.minY - col.scroll)
                addColumn(kids, from: (level, r))
            }
        }
        _ = c
    }

    private func style(_ row: CALayer, node: AXMenus.Node, on: Bool) {
        guard !node.separator else { return }
        let c = theme.colors
        let lit = on && node.enabled
        row.backgroundColor = lit ? themeColor(c.accent).cgColor : nil
        for case let t as CATextLayer in row.sublayers ?? [] {
            let base = themeColor(c.panelText)
            t.foregroundColor = (lit ? NSColor.white : (node.enabled ? base : base.withAlphaComponent(0.35))).cgColor
        }
    }

    private func locate(_ p: CGPoint) -> (Int, Int?)? {
        for (level, col) in columns.enumerated().reversed() where col.frame.contains(p) {
            let y = p.y - col.frame.minY + col.scroll
            var ry: CGFloat = 4
            for (i, node) in col.nodes.enumerated() {
                let h = node.separator ? sepH : rowH
                if y >= ry && y < ry + h { return (level, node.separator ? nil : i) }
                ry += h
            }
            return (level, nil)
        }
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let (level, index) = locate(p) else { return }
        setHover(level, index)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let (level, index) = locate(p) else { onDismiss?(); return }
        guard let index else { return }
        let node = columns[level].nodes[index]
        guard node.enabled else { return }
        // Clicking a submenu row opens it too, for anyone who clicks rather than hovers.
        if node.hasChildren { setHover(level, index); return }
        SoundPlayer.shared.play(.select)
        onPick?(node)
    }

    /// A right-click outside the columns closes the menu (rather than being swallowed by it).
    override func rightMouseDown(with event: NSEvent) {
        if locate(convert(event.locationInWindow, from: nil)) == nil { onDismiss?() }
    }

    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let (level, _) = locate(p) else { return }
        let col = columns[level]
        let full = height(of: col.nodes)
        guard full > col.frame.height else { return }
        col.scroll = min(max(col.scroll - event.scrollingDeltaY, 0), full - col.frame.height)
        while columns.count > level + 1 { columns.removeLast().layer.removeFromSuperlayer() }
        Motion.instant {
            for (i, r) in col.rows.enumerated() {
                let y = col.nodes[..<i].reduce(CGFloat(4)) { $0 + ($1.separator ? sepH : rowH) }
                r.frame.origin.y = y - col.scroll
            }
        }
    }
}
