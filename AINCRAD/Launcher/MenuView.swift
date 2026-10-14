import AppKit
import Carbon.HIToolbox

protocol MenuViewDelegate: AnyObject {
    func menuView(_ view: MenuView, activate item: MenuItem)
    func menuView(_ view: MenuView, childrenOf item: MenuItem) -> [MenuItem]
    func menuViewRequestsClose(_ view: MenuView, reason: String)
    func menuViewDidOpenColumn(_ view: MenuView)
    /// Right-click actions for an item; empty means none.
    func menuView(_ view: MenuView, contextActionsFor item: MenuItem) -> [MenuView.ContextAction]
    func menuView(_ view: MenuView, perform action: String, on item: MenuItem)
    /// Instant results for `query`; slower ones (files) arrive through `more`.
    func menuView(_ view: MenuView, search query: String, more: @escaping ([MenuItem]) -> Void) -> [MenuItem]
}

/// The SAO menu: a column of round root buttons, then cascading columns whose
/// focused row always lines up with the selected root button.
final class MenuView: NSView {
    weak var delegate: MenuViewDelegate?

    struct Hit: Equatable { var level: Int; var index: Int }
    struct ContextAction { let id: String; let title: String; let symbol: String }
    private enum State { case normal, hover, selected }

    private final class Circle {
        let item: MenuItem
        let layer = CALayer(), ring = CALayer(), icon = CALayer(), fill = CAGradientLayer()
        var center = CGPoint.zero
        init(_ item: MenuItem) { self.item = item }
    }

    private final class Row {
        let item: MenuItem
        let layer = CALayer(), badge = CALayer(), icon = CALayer(), label = CATextLayer()
        let fill = CAGradientLayer(), shine = CALayer()
        let iconSpec: String
        var iconTint: String?
        init(_ item: MenuItem) { self.item = item; iconSpec = IconCache.defaultSpec(for: item) }
        var isPlaceholder: Bool { item.action == nil && !item.hasSubmenu }
    }

    private final class Column {
        let items: [MenuItem]
        let container = CALayer(), pointer = CAShapeLayer()
        var rows: [Row] = []
        var focus = 0
        var selected: Int?
        var x: CGFloat = 0
        /// Untransformed frame; the container's own frame changes when `tilt` is applied.
        var frame = CGRect.zero
        init(_ items: [MenuItem]) { self.items = items }
    }

    private var theme = Theme.classic
    private var motion = Motion(spec: .init(), reduced: false)
    private var scale: CGFloat = 1
    private var font = NSFont.systemFont(ofSize: 18)
    private var captionFont = NSFont.systemFont(ofSize: 22)

    private let hostLayer = CALayer()
    private let backdrop = CALayer()
    private let content = CALayer()
    private let caption = CATextLayer()
    private let info = InfoPanel()
    private let hud = HUDLayer()
    /// Name shown in the HUD's player bar.
    var playerName = ""
    var shellOn = false
    /// The screen minus the menu bar and Dock, in this view's coordinates (set per open).
    var safeArea: CGRect?
    private var infoFont = NSFont.systemFont(ofSize: 15)

    /// Silences sounds, e.g. for the invisible warm-up presentation at launch.
    var muted = false

    private func sound(_ event: SoundPlayer.Event) {
        if !muted { SoundPlayer.shared.play(event) }
    }

    /// Decides whether an item is shown right now (hidden flag + visibleWhen conditions).
    var isItemVisible: (MenuItem) -> Bool = { $0.isVisible }

    private var circles: [Circle] = []
    private var columns: [Column] = []
    private var rootFocus = 0
    private var rootSelected: Int?
    private var active = 0
    private var hover: Hit?
    private var anchor = CGPoint.zero
    private var shift: CGFloat = 0
    private var closing = false
    private var generation = 0
    private var scrollAccum: CGFloat = 0
    private var tracking: NSTrackingArea?

    private var g: Theme.Geometry { theme.geometry }
    private var d: CGFloat { g.circleDiameter }
    private var pitch: CGFloat { g.itemHeight + g.itemSpacing }
    private let captionWidth: CGFloat = 170
    private var showInfo: Bool { theme.effects.showInfoPanel }
    private var leftReserve: CGFloat { showInfo ? g.infoPanelWidth + g.infoPanelGap : captionWidth }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        hostLayer.isGeometryFlipped = true
        layer = hostLayer
        wantsLayer = true
        hostLayer.addSublayer(backdrop)
        hostLayer.addSublayer(hud.layer)
        hostLayer.addSublayer(content)
        content.addSublayer(caption)
        content.addSublayer(info.layer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Presenting

    func present(items: [MenuItem], cursor: CGPoint, theme: Theme, motion: Motion, scale: CGFloat) {
        self.theme = theme
        self.motion = motion
        self.scale = scale
        generation += 1
        closing = false
        resolveFonts()
        teardown()

        let visible = items.filter(isItemVisible)
        let pitchRoot = d + g.circleSpacing
        let rootH = max(CGFloat(visible.count) * pitchRoot - g.circleSpacing, d)
        // Open beside the pointer rather than under it; flip to its left near the right edge.
        let dx = CGFloat(g.cursorOffsetX)
        let flip = cursor.x + dx + d / 2 + g.screenMargin > bounds.maxX
        let target = CGPoint(x: cursor.x + (flip ? -dx : dx), y: cursor.y + CGFloat(g.cursorOffsetY))
        anchor = MenuLayout.anchor(cursor: target, bounds: bounds, rootSize: CGSize(width: d, height: rootH),
                                   leftReserve: leftReserve, margin: g.screenMargin)

        Motion.instant {
            backdrop.frame = bounds
            backdrop.backgroundColor = themeColor(theme.colors.backdrop).cgColor
            backdrop.opacity = 1
            content.frame = bounds
            content.opacity = 1
            shift = 0
            let top = anchor.y - rootH / 2
            for (i, item) in visible.enumerated() {
                let c = makeCircle(item)
                c.center = CGPoint(x: anchor.x, y: top + d / 2 + CGFloat(i) * pitchRoot)
                c.layer.frame = CGRect(x: c.center.x - d / 2, y: c.center.y - d / 2, width: d, height: d)
                content.addSublayer(c.layer)
                circles.append(c)
            }
            configureCaption()
            info.configure(theme: theme, titleFont: captionFont, bodyFont: infoFont, scale: scale)
            info.layer.removeAllAnimations()
            info.layer.isHidden = true
            infoShown = false
            rootFocus = 0
            rootSelected = nil
            active = 0
            hover = nil
            query = ""
            searchResults = []
            searchBar.isHidden = true
            context?.column.container.removeFromSuperlayer()
            context = nil
            refreshStates()
        }
        for (i, c) in circles.enumerated() {
            motion.enter(c.layer, offset: CGPoint(x: 0, y: -theme.animation.dropDistance), delay: Double(i) * theme.animation.stagger,
                         duration: theme.animation.open)
        }
        motion.enter(backdrop, offset: .zero, delay: 0, duration: theme.animation.open)
        if theme.effects.hud {
            let h: CGFloat = rootH
            let menuRect = CGRect(x: anchor.x - d / 2 - 12, y: anchor.y - h / 2 - 12, width: d + 24, height: h + 24)
            hud.present(in: safeArea ?? bounds, from: menuRect, theme: theme, motion: motion, scale: scale, stats: hudStats(), showStatus: !shellOn)
        } else {
            Motion.instant { hud.layer.opacity = 0 }
        }
        sound(.open)
    }

    func dismiss(completion: @escaping () -> Void) {
        sound(.close)
        closing = true
        let gen = generation
        CATransaction.begin()
        CATransaction.setAnimationDuration(motion.duration(theme.animation.close))
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == gen else { return }
            self.teardown()
            completion()
        }
        content.opacity = 0
        backdrop.opacity = 0
        hud.dismiss()
        CATransaction.commit()
    }

    private func teardown() {
        Motion.instant {
            circles.forEach { $0.layer.removeFromSuperlayer() }
            columns.forEach { $0.container.removeFromSuperlayer(); $0.pointer.removeFromSuperlayer() }
            caption.string = nil
        }
        circles = []
        columns = []
    }

    /// HP is battery charge on a laptop, free memory on a desktop; LV is hours since start-up.
    private func hudStats() -> HUDLayer.Stats {
        let hub = DataHub.shared
        let name = playerName.isEmpty ? (NSFullUserName().split(separator: " ").first.map(String.init) ?? "Player") : playerName
        let level = Int(ProcessInfo.processInfo.systemUptime / 3600) + 1
        if let b = hub.sample(.battery), let f = b.fraction {
            return .init(name: name, hp: f, hpText: "\(Int(f * 100)) / 100", level: level)
        }
        let m = hub.sample(.memory)
        let free = 1 - (m?.fraction ?? 0)
        let total = (m?.total ?? 0) / 1_048_576
        return .init(name: name, hp: free, hpText: "\(Int(free * total)) / \(Int(total))", level: level)
    }

    private func resolveFonts() {
        font = ThemeFonts.body(theme, theme.font.size)
        captionFont = ThemeFonts.display(theme, theme.font.captionSize * 0.82)
        infoFont = ThemeFonts.body(theme, max(theme.font.size - 3, 11))
    }

    // MARK: Building layers

    private func makeCircle(_ item: MenuItem) -> Circle {
        let c = Circle(item)
        let fx = theme.effects
        c.layer.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        c.layer.cornerRadius = d / 2
        c.layer.borderWidth = fx.borderWidth
        c.layer.borderColor = themeColor(theme.colors.circleBorder).cgColor
        applyShadow(c.layer, path: CGPath(ellipseIn: c.layer.bounds, transform: nil))
        c.ring.frame = c.layer.bounds.insetBy(dx: -5, dy: -5)
        c.ring.cornerRadius = (d + 10) / 2
        c.ring.borderWidth = fx.selectedRingWidth
        c.ring.opacity = 0
        let s = (d * 0.46).rounded()
        c.icon.frame = CGRect(x: (d - s) / 2, y: (d - s) / 2, width: s, height: s)
        c.icon.contentsGravity = .resizeAspect
        c.fill.frame = c.layer.bounds
        c.fill.cornerRadius = d / 2
        c.fill.masksToBounds = true
        c.layer.addSublayer(c.fill)
        c.layer.addSublayer(c.ring)
        c.layer.addSublayer(c.icon)
        return c
    }

    private func makeRow(_ item: MenuItem, index: Int) -> Row {
        let r = Row(item)
        let W = g.itemWidth, H = g.itemHeight
        r.layer.frame = CGRect(x: 0, y: CGFloat(index) * pitch, width: W, height: H)
        r.layer.cornerRadius = g.cornerRadius
        r.layer.borderWidth = theme.effects.borderWidth
        applyShadow(r.layer, path: CGPath(roundedRect: r.layer.bounds, cornerWidth: g.cornerRadius, cornerHeight: g.cornerRadius, transform: nil))

        let b = (H * 0.72).rounded()
        r.badge.frame = CGRect(x: 7, y: ((H - b) / 2).rounded(), width: b, height: b)
        r.badge.cornerRadius = b / 2
        let symbol = IconCache.isSymbol(r.iconSpec)
        r.badge.isHidden = !symbol
        r.icon.frame = symbol ? r.badge.frame.insetBy(dx: (b * 0.22).rounded(), dy: (b * 0.22).rounded()) : r.badge.frame
        r.icon.contentsGravity = .resizeAspect

        let lineH = ceil(font.ascender - font.descender)
        let x = r.badge.frame.maxX + 10
        r.label.frame = CGRect(x: x, y: ((H - lineH) / 2).rounded() + 1, width: W - x - 10, height: lineH)
        r.label.string = item.name
        r.label.font = font
        r.label.fontSize = font.pointSize
        r.label.truncationMode = .end
        r.label.alignmentMode = .left
        r.label.contentsScale = scale
        if r.isPlaceholder { r.layer.opacity = 0.7 }

        r.fill.frame = r.layer.bounds
        r.fill.cornerRadius = g.cornerRadius
        r.fill.masksToBounds = true
        r.shine.frame = CGRect(x: g.cornerRadius, y: 1, width: W - 2 * g.cornerRadius, height: 1)
        r.shine.backgroundColor = NSColor.white.withAlphaComponent(CGFloat(theme.effects.shine)).cgColor
        r.layer.addSublayer(r.fill)
        r.layer.addSublayer(r.shine)
        r.layer.addSublayer(r.badge)
        r.layer.addSublayer(r.icon)
        r.layer.addSublayer(r.label)
        return r
    }

    private func applyShadow(_ layer: CALayer, path: CGPath) {
        setShadow(layer, glow: nil)
        layer.shadowPath = path // avoids an offscreen pass per row
    }

    /// Normal drop shadow, or an accent glow for the selected element.
    private func setShadow(_ layer: CALayer, glow: NSColor?) {
        let fx = theme.effects
        if let glow, fx.selectedGlow > 0 {
            layer.shadowColor = glow.cgColor
            layer.shadowOpacity = Float(fx.glowOpacity)
            layer.shadowRadius = fx.selectedGlow
            layer.shadowOffset = .zero
        } else {
            layer.shadowColor = themeColor(theme.colors.shadow).cgColor
            layer.shadowOpacity = Float(fx.shadowOpacity)
            layer.shadowRadius = fx.shadowRadius
            layer.shadowOffset = CGSize(width: 0, height: 2)
        }
    }

    private func configureCaption() {
        caption.font = captionFont
        caption.fontSize = captionFont.pointSize
        caption.alignmentMode = .right
        caption.truncationMode = .end
        caption.contentsScale = scale
        caption.foregroundColor = themeColor(theme.colors.caption).cgColor
        caption.shadowColor = themeColor(theme.colors.captionShadow).cgColor
        caption.shadowOpacity = 1
        caption.shadowRadius = 4
        caption.shadowOffset = .zero
    }

    private func openColumn(for item: MenuItem, level: Int) {
        let items = (delegate?.menuView(self, childrenOf: item) ?? []).filter(isItemVisible)
        openColumn(items: items, level: level, animate: true)
    }

    private func openColumn(items: [MenuItem], level: Int, animate: Bool, focus: Int = 0) {
        var items = items
        if items.isEmpty { items = [MenuItem(id: "empty", name: "Empty")] }
        let col = Column(items)
        col.focus = min(focus, items.count - 1)
        col.x = anchor.x + d / 2 + g.columnGap + CGFloat(level - 1) * (g.itemWidth + g.columnGap)
        Motion.instant {
            for (i, it) in items.enumerated() {
                let r = makeRow(it, index: i)
                col.container.addSublayer(r.layer)
                col.rows.append(r)
            }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 7))
            path.addLine(to: CGPoint(x: 9, y: 0))
            path.addLine(to: CGPoint(x: 9, y: 14))
            path.closeSubpath()
            col.pointer.path = path
            content.addSublayer(col.pointer)
            content.addSublayer(col.container)
            columns.append(col)
            place(col)
            refreshStates()
        }
        guard animate else { return }
        for (i, r) in col.rows.enumerated() where abs(i - col.focus) <= g.visibleRows {
            motion.enter(r.layer, offset: CGPoint(x: -theme.animation.slideDistance, y: 0), delay: Double(i) * theme.animation.rowStagger,
                         duration: theme.animation.column)
        }
        motion.enter(col.pointer, offset: CGPoint(x: -theme.animation.slideDistance / 2, y: 0), delay: 0, duration: theme.animation.column)
        delegate?.menuViewDidOpenColumn(self)
    }

    // MARK: Search

    private var query = ""
    private var searchResults: [MenuItem] = []
    private let searchBar = CALayer()
    private let searchText = CATextLayer()
    private let searchIcon = CALayer()
    private var searching: Bool { !query.isEmpty }

    /// Typing replaces the columns with one column of results, under an SAO search bar.
    private func setSearch(_ q: String) {
        let wasSearching = searching
        query = q
        guard searching else { return endSearch() }
        searchResults = delegate?.menuView(self, search: q, more: { [weak self] more in
            guard let self, self.query == q, !more.isEmpty else { return }
            // Files go before the "search the web" row, which stays last.
            let web = self.searchResults.firstIndex { $0.id == "search:web" } ?? self.searchResults.count
            self.searchResults.insert(contentsOf: more, at: web)
            self.showResults(animate: false)
        }) ?? []
        if !wasSearching {
            rootSelected = nil
            closeColumns(from: 1)
        }
        showResults(animate: !wasSearching)
        if !wasSearching { sound(.select) }
    }

    private func showResults(animate: Bool) {
        let keepFocus = columns.first.map { $0.focus } ?? 0
        Motion.instant {
            columns.forEach { $0.container.removeFromSuperlayer(); $0.pointer.removeFromSuperlayer() }
            columns = []
        }
        openColumn(items: searchResults.isEmpty ? [MenuItem(id: "empty", name: "No results")] : searchResults,
                   level: 1, animate: animate, focus: animate ? 0 : keepFocus)
        active = 1
        Motion.instant { layoutSearchBar() }
        update()
    }

    private func endSearch() {
        query = ""
        searchResults = []
        delegate.map { _ = $0.menuView(self, search: "", more: { _ in }) }
        closeColumns(from: 1)
        active = 0
        Motion.instant { searchBar.isHidden = true }
        update()
    }

    private func layoutSearchBar() {
        let c = theme.colors
        let x = anchor.x + d / 2 + g.columnGap
        let h = g.itemHeight
        searchBar.frame = CGRect(x: x, y: anchor.y - h / 2 - h - 14, width: g.itemWidth, height: h)
        searchBar.backgroundColor = themeColor(c.hover).cgColor
        searchBar.cornerRadius = h / 2
        searchBar.borderWidth = 1.5
        searchBar.borderColor = themeColor(c.accent).cgColor
        searchBar.shadowColor = themeColor(c.accent).cgColor
        searchBar.shadowOpacity = 0.5
        searchBar.shadowRadius = 8
        searchBar.shadowOffset = .zero
        searchBar.isHidden = false
        let s = (h * 0.5).rounded()
        searchIcon.frame = CGRect(x: 12, y: (h - s) / 2, width: s, height: s)
        searchIcon.contents = IconCache.shared.image("sf:magnifyingglass", size: s, tint: themeColor(c.accent), scale: scale)
        let lineH = ceil(font.ascender - font.descender)
        searchText.frame = CGRect(x: 18 + s, y: (h - lineH) / 2 + 1, width: g.itemWidth - 30 - s, height: lineH)
        searchText.string = query + "▏"
        searchText.font = font
        searchText.fontSize = font.pointSize
        searchText.foregroundColor = themeColor(c.panelText).cgColor
        searchText.truncationMode = .start
        searchText.contentsScale = scale
        if searchBar.superlayer == nil {
            searchBar.addSublayer(searchIcon)
            searchBar.addSublayer(searchText)
            content.addSublayer(searchBar)
        }
    }

    /// Removes columns at `level` and deeper (levels start at 1).
    private func closeColumns(from level: Int) {
        guard level >= 1, columns.count >= level else { return }
        let removed = Array(columns[(level - 1)...])
        columns.removeSubrange((level - 1)...)
        CATransaction.begin()
        CATransaction.setAnimationDuration(motion.duration(0.09))
        CATransaction.setCompletionBlock {
            removed.forEach { $0.container.removeFromSuperlayer(); $0.pointer.removeFromSuperlayer() }
        }
        removed.forEach { $0.container.opacity = 0; $0.pointer.opacity = 0 }
        CATransaction.commit()
    }

    // MARK: Layout & state

    private var parentY: CGFloat {
        guard let s = rootSelected, s < circles.count else { return anchor.y }
        return circles[s].center.y
    }

    private func layoutColumns() {
        columns.forEach(place)
        placeInfo()
        let right = columns.last.map { $0.x + g.itemWidth } ?? anchor.x + d / 2
        shift = MenuLayout.horizontalShift(leftEdge: anchor.x - d / 2 - leftReserve, rightEdge: right,
                                           bounds: bounds, margin: g.screenMargin)
        content.frame = bounds.offsetBy(dx: shift, dy: 0)
    }

    private func place(_ col: Column) {
        let y = parentY
        col.frame = CGRect(x: col.x, y: y - g.itemHeight / 2 - CGFloat(col.focus) * pitch,
                           width: g.itemWidth, height: CGFloat(col.items.count) * pitch)
        // Bounds + position rather than frame, so a tilt transform doesn't move the layout.
        col.container.bounds = CGRect(origin: .zero, size: col.frame.size)
        // Pivot on the focused row: perspective about the middle of a long list (159 apps is
        // ~6800 pt) skews the visible rows badly, so the tilt is centred where the eye is.
        let pivot = (CGFloat(col.focus) * pitch + g.itemHeight / 2) / max(col.frame.height, 1)
        col.container.anchorPoint = CGPoint(x: 0.5, y: pivot)
        col.container.position = CGPoint(x: col.frame.midX, y: col.frame.minY + pivot * col.frame.height)
        col.container.transform = tiltTransform(1)
        col.pointer.frame = CGRect(x: col.x - 12, y: y - 7, width: 9, height: 14)
    }

    /// Perspective turn about the vertical axis; `side` 1 for columns, -1 for the info panel.
    private func tiltTransform(_ side: CGFloat) -> CATransform3D {
        guard theme.effects.tilt != 0 else { return CATransform3DIdentity }
        var t = CATransform3DIdentity
        t.m34 = -1 / 900
        return CATransform3DRotate(t, side * CGFloat(theme.effects.tilt) * .pi / 180, 0, 1, 0)
    }

    private var infoShown = false

    /// The info panel sits beside the chosen root button, centred on it as far as the screen allows.
    private func placeInfo() {
        guard showInfo, !circles.isEmpty else { return }
        let y = circles[min(rootSelected ?? rootFocus, circles.count - 1)].center.y
        info.place(rightX: anchor.x - d / 2 - g.infoPanelGap, centerY: y, pointerY: y,
                   bounds: bounds, margin: g.screenMargin)
        if infoShown { info.layer.transform = tiltTransform(-1) }
    }

    /// Shows the info panel as a bubble growing out of the chosen button, or shrinks it back in.
    /// Hidden until a root button is chosen, so opening the launcher shows only the buttons.
    private func syncInfo() {
        let want = showInfo && rootSelected != nil && !circles.isEmpty && !closing
        guard want != infoShown else { return }
        infoShown = want
        let final = tiltTransform(-1)
        let tail = info.tailOffset
        func bubble(_ s: CGFloat) -> CATransform3D {
            // Scale about the tail point, so the panel appears to come out of the button.
            CATransform3DConcat(CATransform3DConcat(CATransform3DMakeScale(s, s, 1),
                                                    CATransform3DMakeTranslation((1 - s) * tail.x, (1 - s) * tail.y, 0)), final)
        }
        let layer = info.layer
        layer.removeAllAnimations()
        if want {
            Motion.instant {
                layer.isHidden = false
                layer.opacity = 1
                layer.transform = final
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = motion.duration(0.12)
            layer.add(fade, forKey: "fade")
            guard !motion.reduced else { return }
            let pop = CASpringAnimation(keyPath: "transform")
            pop.fromValue = NSValue(caTransform3D: bubble(0.08))
            pop.toValue = NSValue(caTransform3D: final)
            pop.mass = 1
            pop.stiffness = 300
            pop.damping = 24
            pop.initialVelocity = 2
            pop.speed = Float(max(theme.animation.speed, 0.1))
            pop.duration = pop.settlingDuration
            layer.add(pop, forKey: "pop")
        } else {
            CATransaction.begin()
            CATransaction.setAnimationDuration(motion.duration(0.14))
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, !self.infoShown else { return }
                Motion.instant { layer.isHidden = true }
            }
            layer.opacity = 0
            if !motion.reduced { layer.transform = bubble(0.08) }
            CATransaction.commit()
        }
    }

    /// What the info panel describes: the hovered item, else the keyboard focus.
    private func infoTarget() -> (item: MenuItem, children: Int?)? {
        func describe(_ item: MenuItem) -> (MenuItem, Int?) { (item, item.children?.filter(isItemVisible).count) }
        if let h = hover {
            if h.level == 0, h.index < circles.count { return describe(circles[h.index].item) }
            if h.level >= 1, h.level <= columns.count, h.index < columns[h.level - 1].items.count {
                return describe(columns[h.level - 1].items[h.index])
            }
        }
        if active >= 1, active <= columns.count {
            let col = columns[active - 1]
            if col.focus < col.items.count { return describe(col.items[col.focus]) }
        }
        guard !circles.isEmpty else { return nil }
        return describe(circles[min(rootSelected ?? rootFocus, circles.count - 1)].item)
    }

    private func refreshStates() {
        let c = theme.colors
        for (i, circle) in circles.enumerated() {
            let state: State = i == rootSelected ? .selected
                : (hover == Hit(level: 0, index: i) || (active == 0 && i == rootFocus && hover?.level != 0)) ? .hover : .normal
            applyCircle(circle, state)
        }
        for (li, col) in columns.enumerated() {
            let level = li + 1
            col.pointer.fillColor = themeColor(c.accent).cgColor
            for (i, row) in col.rows.enumerated() {
                // The mouse takes over the highlight in a column it is hovering.
                let state: State = i == col.selected ? .selected
                    : (hover == Hit(level: level, index: i) || (active == level && i == col.focus && hover?.level != level)) ? .hover : .normal
                let dist = i - col.focus
                row.layer.opacity = MenuLayout.rowOpacity(distance: dist, visibleRows: g.visibleRows) * (row.isPlaceholder ? 0.7 : 1)
                applyRow(row, state, loadIcon: abs(dist) <= g.visibleRows)
            }
        }
        syncInfo()
        updateCaption()
        if infoShown, let target = infoTarget() {
            info.show(target.item, detail: InfoPanel.detail(for: target.item, childCount: target.children),
                      iconSpec: IconCache.defaultSpec(for: target.item))
        }
        announceFocus()
    }

    private var announcedID: String?

    /// The menu is drawn with layers, so VoiceOver hears the focused item through announcements.
    private func announceFocus() {
        guard NSWorkspace.shared.isVoiceOverEnabled, !muted, let target = infoTarget(), target.item.id != announcedID else { return }
        announcedID = target.item.id
        let kind = target.item.hasSubmenu ? "submenu" : target.item.action == nil ? "" : "button"
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: "\(target.item.name), \(kind)",
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .menu }
    override func accessibilityLabel() -> String? {
        "AINCRAD launcher. Arrow keys move, Return opens, Escape closes."
    }

    /// Top-to-bottom gradient colours for a fill, keeping the colour's own opacity.
    private func shade(_ color: NSColor) -> [CGColor] {
        let c = color.usingColorSpace(.sRGB) ?? color
        let g = CGFloat(theme.effects.gradient)
        let top = (c.blended(withFraction: g, of: .white) ?? c).withAlphaComponent(c.alphaComponent)
        let bottom = (c.blended(withFraction: g, of: .black) ?? c).withAlphaComponent(c.alphaComponent)
        return [top.cgColor, bottom.cgColor]
    }

    private func accent(_ item: MenuItem) -> NSColor {
        themeColor(item.accent ?? theme.colors.accent)
    }

    private func applyCircle(_ circle: Circle, _ state: State) {
        let c = theme.colors
        let tint: NSColor
        switch state {
        case .selected:
            circle.fill.colors = shade(accent(circle.item))
            circle.ring.borderColor = accent(circle.item).cgColor
            circle.ring.opacity = 1
            tint = themeColor(c.accentText)
            setShadow(circle.layer, glow: accent(circle.item))
        case .hover:
            circle.fill.colors = shade(themeColor(c.hover))
            circle.ring.borderColor = accent(circle.item).cgColor
            circle.ring.opacity = 0.6
            tint = accent(circle.item)
            setShadow(circle.layer, glow: nil)
        case .normal:
            circle.fill.colors = shade(themeColor(c.circle))
            circle.ring.opacity = 0
            tint = themeColor(c.circleIcon)
            setShadow(circle.layer, glow: nil)
        }
        let spec = IconCache.defaultSpec(for: circle.item)
        circle.icon.contents = IconCache.shared.image(spec, size: circle.icon.bounds.width,
                                                      tint: IconCache.isSymbol(spec) ? tint : nil, scale: scale)
    }

    private func applyRow(_ row: Row, _ state: State, loadIcon: Bool) {
        let c = theme.colors
        let glyph: String
        switch state {
        case .selected:
            row.fill.colors = shade(accent(row.item))
            row.layer.borderColor = accent(row.item).cgColor
            row.label.foregroundColor = themeColor(c.accentText).cgColor
            row.badge.backgroundColor = themeColor(c.accentText).cgColor
            glyph = row.item.accent ?? c.accent
            setShadow(row.layer, glow: accent(row.item))
        case .hover:
            row.fill.colors = shade(themeColor(c.hover))
            row.layer.borderColor = accent(row.item).cgColor
            row.label.foregroundColor = themeColor(c.panelText).cgColor
            row.badge.backgroundColor = accent(row.item).cgColor
            glyph = c.iconGlyph
            setShadow(row.layer, glow: nil)
        case .normal:
            row.fill.colors = shade(themeColor(c.panel))
            row.layer.borderColor = themeColor(c.panelBorder).cgColor
            row.label.foregroundColor = themeColor(c.panelText).cgColor
            row.badge.backgroundColor = themeColor(c.iconBadge).cgColor
            glyph = c.iconGlyph
            setShadow(row.layer, glow: nil)
        }
        let symbol = IconCache.isSymbol(row.iconSpec)
        let wanted = symbol ? glyph : "-"
        guard loadIcon, row.iconTint != wanted else { return }
        row.iconTint = wanted
        row.icon.contents = IconCache.shared.image(row.iconSpec, size: row.icon.bounds.width,
                                                   tint: symbol ? themeColor(glyph) : nil, scale: scale)
    }

    private func updateCaption() {
        guard !infoShown, !searching else { caption.opacity = 0; return }
        let index: Int? = hover.flatMap { $0.level == 0 ? $0.index : nil } ?? (active == 0 ? rootFocus : rootSelected)
        guard let i = index, i < circles.count else { caption.opacity = 0; return }
        let lineH = ceil(captionFont.ascender - captionFont.descender)
        let name = circles[i].item.name
        caption.string = name
        // As wide as the name needs (wide display fonts like Orbitron overflow a fixed width),
        // but never off the left of the screen.
        let right = anchor.x - d / 2 - 16
        let w = min(ceil((name as NSString).size(withAttributes: [.font: captionFont]).width) + 6, max(right + shift - 8, captionWidth))
        caption.frame = CGRect(x: right - w, y: circles[i].center.y - lineH / 2 + 1, width: w, height: lineH)
        caption.opacity = 1
    }

    private func update() {
        motion.animate(theme.animation.move) {
            layoutColumns()
            refreshStates()
        }
    }

    // MARK: Hit testing

    func hit(_ p: CGPoint) -> Hit? {
        let q = CGPoint(x: p.x - shift, y: p.y)
        for (i, c) in circles.enumerated() where hypot(q.x - c.center.x, q.y - c.center.y) <= d / 2 + 4 {
            return Hit(level: 0, index: i)
        }
        for (li, col) in columns.enumerated() {
            let f = col.frame
            let local = CGPoint(x: q.x - f.minX, y: q.y - f.minY)
            guard local.x >= 0, local.x <= g.itemWidth, local.y >= 0 else { continue }
            let i = Int(local.y / pitch)
            if i < col.rows.count, local.y - CGFloat(i) * pitch <= g.itemHeight,
               MenuLayout.rowOpacity(distance: i - col.focus, visibleRows: g.visibleRows) > 0.3 {
                return Hit(level: li + 1, index: i)
            }
        }
        return nil
    }

    private func columnLevel(atX x: CGFloat) -> Int? {
        let qx = x - shift
        return columns.firstIndex { qx >= $0.x && qx <= $0.x + g.itemWidth }.map { $0 + 1 }
    }

    // MARK: Navigation

    func click(_ h: Hit) {
        guard !closing else { return }
        if h.level == 0 {
            guard h.index < circles.count else { return }
            if searching {
                query = ""
                Motion.instant { searchBar.isHidden = true }
            }
            let item = circles[h.index].item
            rootFocus = h.index
            if rootSelected == h.index {
                rootSelected = nil
                closeColumns(from: 1)
                active = 0
                sound(.back)
                return update()
            }
            sound(.select)
            rootSelected = h.index
            closeColumns(from: 1)
            update()
            if item.hasSubmenu {
                active = 1
                openColumn(for: item, level: 1)
                update()
            } else {
                activate(item)
            }
            return
        }
        guard h.level <= columns.count else { return }
        let col = columns[h.level - 1]
        guard h.index < col.items.count else { return }
        let item = col.items[h.index]
        guard item.action != nil || item.hasSubmenu else { return sound(.error) }
        sound(.select)
        if col.selected == h.index, columns.count > h.level {
            active = h.level + 1
            return update()
        }
        col.focus = h.index
        col.selected = h.index
        closeColumns(from: h.level + 1)
        if item.hasSubmenu {
            active = h.level + 1
            update()
            openColumn(for: item, level: h.level + 1)
            update()
        } else {
            active = h.level
            update()
            activate(item)
        }
    }

    private func activate(_ item: MenuItem) {
        guard item.action != nil else { return }
        closing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + motion.duration(0.08)) { [weak self] in
            guard let self else { return }
            self.delegate?.menuView(self, activate: item)
        }
    }

    private func setFocus(_ index: Int) {
        if active == 0 {
            rootFocus = min(max(index, 0), circles.count - 1)
        } else {
            let col = columns[active - 1]
            let n = min(max(index, 0), col.items.count - 1)
            guard n != col.focus || col.selected != nil else { return }
            col.focus = n
            col.selected = nil
            closeColumns(from: active + 1)
        }
        update()
    }

    private var currentFocus: Int { active == 0 ? rootFocus : columns[active - 1].focus }

    private func enter() {
        click(active == 0 ? Hit(level: 0, index: rootFocus) : Hit(level: active, index: columns[active - 1].focus))
    }

    private func back(closeAtRoot: Bool) {
        if active == 0 {
            if closeAtRoot { delegate?.menuViewRequestsClose(self, reason: "back at root") }
            return
        }
        closeColumns(from: active)
        sound(.back)
        active -= 1
        if active == 0 { rootSelected = nil } else { columns[active - 1].selected = nil }
        update()
    }

    /// Makes `level` the keyboard/scroll target without changing what's open above it.
    private func makeActive(_ level: Int) {
        guard level != active, level >= 1, level <= columns.count else { return }
        closeColumns(from: level + 1)
        active = level
        columns[level - 1].selected = nil
    }

    /// Named keys, shared by the keyboard and the aincrad://key/<name> automation hook.
    func handleKey(named name: String) {
        guard !closing, !circles.isEmpty else { return }
        switch name {
        case "up": setFocus(currentFocus - 1)
        case "down": setFocus(currentFocus + 1)
        case "right", "enter": enter()
        case "left": searching && active <= 1 ? endSearch() : back(closeAtRoot: false)
        case "back": searching ? setSearch(String(query.dropLast())) : back(closeAtRoot: true)
        case "escape":
            if context != nil { closeContext() } else if searching { endSearch() } else { delegate?.menuViewRequestsClose(self, reason: "escape") }
        default: break
        }
    }

    // MARK: Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        guard !closing else { return }
        if context != nil {
            let i = contextIndex(convert(event.locationInWindow, from: nil))
            if i != contextHover { contextHover = i; if i != nil { sound(.hover) }; refreshContext() }
            return
        }
        let h = hit(convert(event.locationInWindow, from: nil))
        guard h != hover else { return }
        hover = h
        if h != nil { sound(.hover) }
        motion.animate(theme.animation.highlight) { refreshStates() }
    }

    override func mouseDown(with event: NSEvent) {
        guard !closing else { return }
        if let c = context {
            if let i = contextIndex(convert(event.locationInWindow, from: nil)) {
                closeContext()
                sound(.select)
                delegate?.menuView(self, perform: c.actions[i].id, on: c.item)
            } else {
                closeContext()
            }
            return
        }
        if let h = hit(convert(event.locationInWindow, from: nil)) {
            click(h)
        } else {
            delegate?.menuViewRequestsClose(self, reason: "click outside")
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !closing else { return }
        let p = convert(event.locationInWindow, from: nil)
        if context != nil { return closeContext() }
        if let h = hit(p), let item = item(at: h), let actions = delegate?.menuView(self, contextActionsFor: item), !actions.isEmpty {
            showContext(actions, for: item, at: p)
        } else {
            back(closeAtRoot: true)
        }
    }

    // MARK: Context actions

    private var context: (column: Column, item: MenuItem, actions: [ContextAction])?
    private var contextHover: Int?

    private func item(at h: Hit) -> MenuItem? {
        if h.level == 0 { return h.index < circles.count ? circles[h.index].item : nil }
        guard h.level <= columns.count, h.index < columns[h.level - 1].items.count else { return nil }
        let item = columns[h.level - 1].items[h.index]
        return item.action == nil && !item.hasSubmenu ? nil : item
    }

    /// A small SAO column of actions at the pointer, built from the same rows as the menu.
    private func showContext(_ actions: [ContextAction], for item: MenuItem, at p: CGPoint) {
        let rows = actions.map { MenuItem(id: "ctx:" + $0.id, name: $0.title, icon: "sf:" + $0.symbol, action: .builtin("none")) }
        let col = Column(rows)
        let width = g.itemWidth * 0.9
        let height = CGFloat(rows.count) * pitch
        let x = min(p.x - shift + 10, bounds.maxX - shift - width - 10)
        let y = min(p.y - g.itemHeight / 2, bounds.maxY - height - 10)
        Motion.instant {
            for (i, it) in rows.enumerated() {
                let r = makeRow(it, index: i)
                r.layer.bounds.size.width = width
                r.layer.position.x = width / 2
                r.fill.frame.size.width = width
                r.shine.frame.size.width = width - 2 * g.cornerRadius
                r.label.frame.size.width = width - r.label.frame.minX - 10
                r.layer.shadowPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: g.itemHeight),
                                            cornerWidth: g.cornerRadius, cornerHeight: g.cornerRadius, transform: nil)
                col.container.addSublayer(r.layer)
                col.rows.append(r)
                applyRow(r, .normal, loadIcon: true)
            }
            col.container.frame = CGRect(x: x, y: y, width: width, height: height)
            // Tilted columns are 3D planes and would cut through a flat menu laid over them.
            col.container.zPosition = 400
            col.frame = col.container.frame
            content.addSublayer(col.container)
        }
        for (i, r) in col.rows.enumerated() {
            motion.enter(r.layer, offset: CGPoint(x: -8, y: 0), delay: Double(i) * 0.015, duration: 0.12)
        }
        context = (col, item, actions)
        contextHover = nil
        sound(.select)
    }

    private func closeContext() {
        guard let c = context else { return }
        context = nil
        contextHover = nil
        CATransaction.begin()
        CATransaction.setAnimationDuration(motion.duration(0.08))
        CATransaction.setCompletionBlock { c.column.container.removeFromSuperlayer() }
        c.column.container.opacity = 0
        CATransaction.commit()
    }

    private func contextIndex(_ p: CGPoint) -> Int? {
        guard let c = context else { return nil }
        let q = CGPoint(x: p.x - shift - c.column.frame.minX, y: p.y - c.column.frame.minY)
        guard q.x >= 0, q.x <= c.column.frame.width, q.y >= 0 else { return nil }
        let i = Int(q.y / pitch)
        return i < c.actions.count && q.y - CGFloat(i) * pitch <= g.itemHeight ? i : nil
    }

    private func refreshContext() {
        guard let c = context else { return }
        motion.animate(theme.animation.highlight) {
            for (i, r) in c.column.rows.enumerated() { applyRow(r, i == contextHover ? .hover : .normal, loadIcon: true) }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard !closing else { return }
        let level = columnLevel(atX: convert(event.locationInWindow, from: nil).x) ?? active
        guard level >= 1 else { return }
        if event.phase == .began { scrollAccum = 0 }
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 22 : 1
        scrollAccum += event.scrollingDeltaY
        while abs(scrollAccum) >= step {
            let up = scrollAccum > 0
            scrollAccum += up ? -step : step
            makeActive(level)
            setFocus(currentFocus + (up ? -1 : 1))
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !closing else { return }
        switch Int(event.keyCode) {
        case kVK_Escape: handleKey(named: "escape")
        case kVK_UpArrow: handleKey(named: "up")
        case kVK_DownArrow: handleKey(named: "down")
        case kVK_RightArrow, kVK_Return, kVK_ANSI_KeypadEnter: handleKey(named: "enter")
        case kVK_LeftArrow: handleKey(named: "left")
        case kVK_Delete: handleKey(named: "back")
        case kVK_Space where !searching: handleKey(named: "enter")
        default:
            // Typing searches. Command/Control shortcuts are left alone.
            guard event.modifierFlags.intersection([.command, .control]).isEmpty,
                  let chars = event.characters, !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
            setSearch(query + chars)
        }
    }
}
