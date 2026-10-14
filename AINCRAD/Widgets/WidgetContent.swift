import AppKit

/// Shared look and lifecycle for one widget's layers. Subclasses draw a type; `start`/`stop`
/// bracket the time the widget is actually visible, so hidden widgets cost nothing.
class WidgetContent {
    let root = CALayer()
    let config: WidgetConfig
    let theme: Theme
    let accent: NSColor
    let scale: CGFloat
    var onLaunchMenu: ((CGRect) -> Void)?

    var size: CGSize { CGSize(width: config.width, height: config.height) }
    var textColor: NSColor {
        themeColor(config.style.textColor ?? (config.style.showPanel ? theme.colors.panelText : "#FFFFFF"))
    }

    required init(config: WidgetConfig, theme: Theme, accent: NSColor, scale: CGFloat) {
        self.config = config
        self.theme = theme
        self.accent = accent
        self.scale = scale
        root.bounds = CGRect(origin: .zero, size: size)
        if config.style.showPanel {
            root.backgroundColor = themeColor(config.style.background ?? theme.colors.panel).cgColor
            root.cornerRadius = theme.geometry.cornerRadius
            root.borderWidth = theme.effects.borderWidth
            root.borderColor = themeColor(theme.colors.panelBorder).cgColor
        }
        if config.style.shadow {
            root.shadowColor = themeColor(theme.colors.shadow).cgColor
            root.shadowOpacity = Float(theme.effects.shadowOpacity)
            root.shadowRadius = 8
            root.shadowOffset = CGSize(width: 0, height: 2)
            if config.style.showPanel {
                root.shadowPath = CGPath(roundedRect: root.bounds, cornerWidth: theme.geometry.cornerRadius,
                                         cornerHeight: theme.geometry.cornerRadius, transform: nil)
            }
        }
        build()
    }

    func build() {}
    func start() {}
    func stop() {}
    func click(at point: CGPoint, in screenRect: CGRect) {}
    func setHover(_ on: Bool) {}
    /// Pointer position over the widget (nil when it leaves), for widgets with several targets.
    func hover(at point: CGPoint?) {}

    func font(_ size: Double) -> NSFont {
        ThemeFonts.make(config.style.font ?? theme.font.family, size)
    }

    func text(_ string: String, size: Double, color: NSColor? = nil, align: CATextLayerAlignmentMode = .left) -> CATextLayer {
        let t = CATextLayer()
        let f = font(size)
        t.font = f
        t.fontSize = f.pointSize
        t.string = string
        t.foregroundColor = (color ?? textColor).cgColor
        t.alignmentMode = align
        t.truncationMode = .end
        t.contentsScale = scale
        if !config.style.showPanel {
            t.shadowColor = NSColor.black.cgColor
            t.shadowOpacity = 0.8
            t.shadowRadius = 3
            t.shadowOffset = .zero
        }
        root.addSublayer(t)
        return t
    }

    func lineHeight(_ size: Double) -> CGFloat {
        let f = font(size)
        return ceil(f.ascender - f.descender)
    }
}

// MARK: Clock

final class ClockContent: WidgetContent {
    private var time: CATextLayer!
    private var date: CATextLayer?
    private var timer: Timer?
    private let timeFormatter = DateFormatter()
    private let dateFormatter = DateFormatter()

    override func build() {
        timeFormatter.dateFormat = config.prop("format", "HH:mm")
        let datePattern = config.prop("date", "")
        let big = config.style.fontSize * 2.6
        let small = config.style.fontSize
        let bh = lineHeight(big), sh = datePattern.isEmpty ? 0 : lineHeight(small)
        let top = (size.height - bh - sh - 8) / 2
        time = text("", size: big, align: .center)
        time.frame = CGRect(x: 8, y: top, width: size.width - 16, height: bh)
        let bar = CALayer()
        bar.backgroundColor = accent.cgColor
        bar.frame = CGRect(x: size.width * 0.3, y: top + bh + 2, width: size.width * 0.4, height: 2)
        root.addSublayer(bar)
        if !datePattern.isEmpty {
            dateFormatter.dateFormat = datePattern
            let d = text("", size: small, align: .center)
            d.frame = CGRect(x: 8, y: top + bh + 8, width: size.width - 16, height: sh)
            date = d
        }
        refresh()
    }

    override func start() {
        refresh()
        schedule()
    }

    override func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Fires on the next second or minute boundary, depending on whether the format shows seconds.
    private func schedule() {
        let perSecond = timeFormatter.dateFormat.contains("s")
        let now = Date().timeIntervalSinceReferenceDate
        let step = perSecond ? 1.0 : 60.0
        let next = Date(timeIntervalSinceReferenceDate: (now / step).rounded(.down) * step + step + 0.01)
        let t = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            self?.refresh()
            self?.schedule()
        }
        t.tolerance = perSecond ? 0.05 : 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func refresh() {
        let now = Date()
        Motion.instant {
            time.string = timeFormatter.string(from: now)
            date?.string = dateFormatter.string(from: now)
        }
    }
}

// MARK: Stat (CPU, memory, disk, battery, network, uptime)

final class StatContent: WidgetContent {
    private var value: CATextLayer!
    private var fill: CALayer?
    private var ring: CAShapeLayer?
    private var token: DataHub.Token?
    private var sourceKey: String { config.prop("source", "cpu") }
    private var barWidth: CGFloat = 0

    override func build() {
        let fs = config.style.fontSize
        let show = config.prop("show", "bar")
        let pad: CGFloat = 12
        let lh = lineHeight(fs)
        var labelX = pad
        if show == "ring" {
            let d = min(size.height - 16, 60)
            let track = CAShapeLayer(), arc = CAShapeLayer()
            let rect = CGRect(x: pad, y: (size.height - d) / 2, width: d, height: d)
            // A full circle starting at 12 o'clock, so strokeEnd fills clockwise from the top.
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: d / 2 - 3,
                        startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: false)
            for (l, color) in [(track, textColor.withAlphaComponent(0.15)), (arc, accent)] {
                l.path = path
                l.fillColor = nil
                l.strokeColor = color.cgColor
                l.lineWidth = 6
                l.lineCap = .round
                root.addSublayer(l)
            }
            arc.strokeEnd = 0
            ring = arc
            labelX = rect.maxX + 12
        }
        let label = text(config.prop("label", DataHub.shared.title(for: sourceKey)).uppercased(), size: fs * 0.8)
        label.frame = CGRect(x: labelX, y: show == "bar" ? 10 : size.height / 2 - lh, width: size.width - labelX - pad, height: lh)
        value = text("…", size: fs, align: show == "ring" ? .left : .right)
        value.frame = show == "ring"
            ? CGRect(x: labelX, y: size.height / 2, width: size.width - labelX - pad, height: lh)
            : CGRect(x: pad, y: 10, width: size.width - pad * 2, height: lh)
        if show == "bar" {
            barWidth = size.width - pad * 2
            let track = CALayer()
            track.frame = CGRect(x: pad, y: size.height - 22, width: barWidth, height: 8)
            track.backgroundColor = textColor.withAlphaComponent(0.15).cgColor
            track.cornerRadius = 2
            root.addSublayer(track)
            let f = CALayer()
            f.anchorPoint = .zero
            f.frame = CGRect(x: pad, y: size.height - 22, width: 0, height: 8)
            f.backgroundColor = accent.cgColor
            f.cornerRadius = 2
            root.addSublayer(f)
            fill = f
        }
    }

    override func start() {
        guard token == nil else { return }
        token = DataHub.shared.subscribe(key: sourceKey) { [weak self] in self?.show($0) }
    }

    override func stop() {
        if let token { DataHub.shared.unsubscribe(token) }
        token = nil
    }

    /// Instant, not animated: a 0.4 s bar animation every 2 s kept WindowServer compositing
    /// continuously (measured +10 points of its CPU with 7 widgets over an animated wallpaper).
    private func show(_ s: StatSample) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        value.string = s.text
        if let f = s.fraction {
            fill?.bounds.size.width = barWidth * CGFloat(min(max(f, 0), 1))
            ring?.strokeEnd = CGFloat(min(max(f, 0), 1))
        }
        CATransaction.commit()
    }

    deinit { stop() }
}

// MARK: SAO HP bars

final class HPBarContent: WidgetContent {
    private struct Row { let name: String; let source: StatSource; let fill: CALayer; let width: CGFloat; let readout: CATextLayer? }
    private var rows: [Row] = []
    private var level: CATextLayer?
    private var tokens: [DataHub.Token] = []

    static let green = NSColor(srgbRed: 0.56, green: 0.86, blue: 0.24, alpha: 1)
    static let yellow = NSColor(srgbRed: 0.95, green: 0.78, blue: 0.19, alpha: 1)
    static let red = NSColor(srgbRed: 0.89, green: 0.28, blue: 0.23, alpha: 1)

    /// "Kirito:cpu, Asuna:memory" → [(Kirito, cpu), …]
    static func parseRows(_ text: String) -> [(String, StatSource)] {
        text.split(separator: ",").compactMap { part in
            let bits = part.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard bits.count == 2, let s = StatSource(rawValue: bits[1].lowercased()) else { return nil }
            return (bits[0], s)
        }
    }

    override func build() {
        let parsed = HPBarContent.parseRows(config.prop("rows", "Player:cpu"))
        guard !parsed.isEmpty else { return }
        let pad: CGFloat = 12, fs = config.style.fontSize
        let mainH: CGFloat = max(26, fs * 1.5), subH: CGFloat = max(18, fs * 1.05)
        let readoutH = lineHeight(fs * 0.8) + 4
        let nameW = min(110, size.width * 0.28)
        var y: CGFloat = pad
        for (i, (name, source)) in parsed.enumerated() {
            let h = i == 0 ? mainH : subH
            let barX = pad + nameW + 8
            let barW = (i == 0 ? size.width - pad : size.width * 0.72) - barX
            let label = text(name, size: i == 0 ? fs : fs * 0.82)
            label.frame = CGRect(x: pad + 6, y: y + (h - lineHeight(i == 0 ? fs : fs * 0.82)) / 2 + 1, width: nameW - 6, height: lineHeight(fs))
            let marker = CALayer()
            marker.frame = CGRect(x: pad, y: y + 3, width: 3, height: h - 6)
            marker.backgroundColor = accent.cgColor
            root.addSublayer(marker)

            // Slanted SAO bar: the right end cuts diagonally.
            let slant = h * 0.6
            let shape = CGMutablePath()
            shape.move(to: CGPoint(x: 0, y: 0))
            shape.addLine(to: CGPoint(x: barW, y: 0))
            shape.addLine(to: CGPoint(x: barW - slant, y: h))
            shape.addLine(to: CGPoint(x: 0, y: h))
            shape.closeSubpath()
            let track = CAShapeLayer()
            track.frame = CGRect(x: barX, y: y, width: barW, height: h)
            track.path = shape
            track.fillColor = NSColor.black.withAlphaComponent(0.35).cgColor
            track.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
            track.lineWidth = 1.5
            root.addSublayer(track)
            let mask = CAShapeLayer()
            mask.path = shape
            let fillHolder = CALayer()
            fillHolder.frame = CGRect(x: barX, y: y, width: barW, height: h)
            fillHolder.mask = mask
            let fill = CALayer()
            fill.anchorPoint = .zero
            fill.frame = CGRect(x: 0, y: 2, width: 0, height: h - 4)
            fill.backgroundColor = HPBarContent.green.cgColor
            fillHolder.addSublayer(fill)
            root.addSublayer(fillHolder)

            var readout: CATextLayer?
            if i == 0 {
                let r = text("—", size: fs * 0.8, color: .white, align: .center)
                r.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
                r.frame = CGRect(x: size.width - pad - 210, y: y + h + 4, width: 130, height: readoutH)
                readout = r
                let lv = text("LV: 1", size: fs * 0.8, color: .white, align: .center)
                lv.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
                lv.frame = CGRect(x: size.width - pad - 74, y: y + h + 4, width: 74, height: readoutH)
                level = lv
                y += readoutH + 6
            }
            rows.append(Row(name: name, source: source, fill: fill, width: barW, readout: readout))
            y += h + 8
        }
    }

    override func start() {
        guard tokens.isEmpty else { return }
        for (i, row) in rows.enumerated() {
            tokens.append(DataHub.shared.subscribe(row.source) { [weak self] in self?.show($0, row: i) })
        }
        let levelSpec = config.prop("level", "uptime")
        if levelSpec == "uptime" {
            tokens.append(DataHub.shared.subscribe(.uptime) { [weak self] s in
                Motion.instant { self?.level?.string = "LV: \(Int((s.used ?? 0) / 3600) + 1)" }
            })
        } else {
            level?.string = "LV: \(levelSpec)"
        }
    }

    override func stop() {
        tokens.forEach { DataHub.shared.unsubscribe($0) }
        tokens = []
    }

    /// HP is what's left: free CPU, free memory, free disk, battery charge.
    private func show(_ s: StatSample, row i: Int) {
        guard rows.indices.contains(i), let used = s.fraction else { return }
        let row = rows[i]
        let hp = row.source == .battery ? used : 1 - used
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        row.fill.bounds.size.width = row.width * CGFloat(min(max(hp, 0), 1))
        row.fill.backgroundColor = (hp > 0.5 ? HPBarContent.green : hp > 0.2 ? HPBarContent.yellow : HPBarContent.red).cgColor
        if let r = row.readout, let total = s.total, let usedValue = s.used {
            let free = row.source == .battery ? usedValue : total - usedValue
            let unit = row.source == .memory ? 1_048_576.0 : row.source == .disk ? 1_073_741_824.0 : 1
            r.string = "\(Int(free / unit)) / \(Int(total / unit))"
        }
        CATransaction.commit()
    }

    deinit { stop() }
}

// MARK: Text, image

final class TextContent: WidgetContent {
    override func build() {
        let align: CATextLayerAlignmentMode = ["left": .left, "right": .right][config.prop("align", "center")] ?? .center
        let t = text(config.prop("text", ""), size: config.style.fontSize, align: align)
        t.isWrapped = true
        let lines = CGFloat(max(1, config.prop("text", "").split(separator: "\n", omittingEmptySubsequences: false).count))
        let h = min(size.height - 16, lineHeight(config.style.fontSize) * lines * 1.6)
        t.frame = CGRect(x: 10, y: (size.height - h) / 2, width: size.width - 20, height: h)
    }
}

final class ImageContent: WidgetContent {
    override func build() {
        let path = (config.prop("path", "") as NSString).expandingTildeInPath
        let img = CALayer()
        img.frame = root.bounds.insetBy(dx: config.style.showPanel ? 6 : 0, dy: config.style.showPanel ? 6 : 0)
        img.contentsGravity = config.prop("fit", "fit") == "fill" ? .resizeAspectFill : .resizeAspect
        img.masksToBounds = true
        img.cornerRadius = theme.geometry.cornerRadius
        if let image = NSImage(contentsOfFile: path) {
            img.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else {
            let hint = text(path.isEmpty ? "Choose an image in Settings › Widgets" : "Image not found", size: 13, align: .center)
            hint.frame = CGRect(x: 6, y: size.height / 2 - 10, width: size.width - 12, height: 20)
        }
        root.addSublayer(img)
    }
}

// MARK: Interactive: app shortcut, launcher button

final class AppContent: WidgetContent {
    private let icon = CALayer()

    override func build() {
        let target = config.prop("target", "com.apple.finder")
        let url = ActionRunner.appURL(target)
        let showLabel = config.flag("label", true)
        let lh = showLabel ? lineHeight(config.style.fontSize) : 0
        let side = min(size.width - 16, size.height - lh - 16)
        icon.frame = CGRect(x: (size.width - side) / 2, y: 8, width: side, height: side)
        icon.contents = url.flatMap { IconCache.shared.image("app:" + $0.path, size: side, tint: nil, scale: scale) }
        root.addSublayer(icon)
        if showLabel {
            let name = config.prop("name", url.map { AppScanner.displayName($0.path) } ?? target)
            let t = text(name, size: config.style.fontSize, align: .center)
            t.frame = CGRect(x: 4, y: icon.frame.maxY + 4, width: size.width - 8, height: lh)
        }
    }

    override func click(at point: CGPoint, in screenRect: CGRect) {
        ActionRunner.run(.app(config.prop("target", "com.apple.finder")), builtin: { _ in })
    }

    override func setHover(_ on: Bool) {
        icon.transform = on ? CATransform3DMakeScale(1.08, 1.08, 1) : CATransform3DIdentity
        icon.shadowColor = accent.cgColor
        icon.shadowRadius = 10
        icon.shadowOpacity = on ? 0.8 : 0
    }
}

final class LauncherButtonContent: WidgetContent {
    private let circle = CALayer()

    override func build() {
        let label = config.prop("label", "Menu")
        let lh = label.isEmpty ? 0 : lineHeight(config.style.fontSize)
        let d = min(size.width - 16, size.height - lh - 16)
        circle.frame = CGRect(x: (size.width - d) / 2, y: 8, width: d, height: d)
        circle.cornerRadius = d / 2
        circle.backgroundColor = themeColor(theme.colors.circle).cgColor
        circle.borderWidth = 2
        circle.borderColor = accent.cgColor
        circle.shadowColor = accent.cgColor
        circle.shadowRadius = 10
        circle.shadowOpacity = 0.5
        circle.shadowOffset = .zero
        let glyph = CALayer()
        let s = d * 0.46
        glyph.frame = CGRect(x: (d - s) / 2, y: (d - s) / 2, width: s, height: s)
        glyph.contents = IconCache.shared.image(config.prop("icon", "sf:circle.grid.cross.fill"), size: s, tint: accent, scale: scale)
        circle.addSublayer(glyph)
        root.addSublayer(circle)
        if !label.isEmpty {
            let t = text(label, size: config.style.fontSize, align: .center)
            t.frame = CGRect(x: 2, y: circle.frame.maxY + 4, width: size.width - 4, height: lh)
        }
    }

    override func click(at point: CGPoint, in screenRect: CGRect) { onLaunchMenu?(screenRect) }

    override func setHover(_ on: Bool) {
        circle.backgroundColor = (on ? accent : themeColor(theme.colors.circle)).cgColor
        circle.shadowOpacity = on ? 0.9 : 0.5
    }
}

// MARK: Game shelf

/// A row of game covers; clicking one launches it. Covers come from the launcher's own art.
final class GameShelfContent: WidgetContent {
    private var games: [GameLibrary.Game] = []
    private var slots: [CGRect] = []
    private var tiles: [CALayer] = []
    private var hovered: Int?

    override func build() {
        let t = text("Loading games…", size: 14, align: .center)
        t.frame = CGRect(x: 0, y: size.height / 2 - 10, width: size.width, height: 20)
        // Scanned off the main thread: a Steam library can live in iCloud Drive.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let all = GameLibrary.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                t.removeFromSuperlayer()
                self.populate(all)
            }
        }
    }

    private func populate(_ all: [GameLibrary.Game]) {
        let source = config.prop("source", "all")
        games = Array((source == "all" ? all : all.filter { $0.source.lowercased() == source.lowercased() })
            .sorted { ($0.cover != nil ? 0 : 1) < ($1.cover != nil ? 0 : 1) })
        let pad: CGFloat = 10, labelH: CGFloat = config.flag("titles", true) ? lineHeight(12) + 2 : 0
        let h = size.height - pad * 2 - labelH
        let w = (h * 2 / 3).rounded()
        let count = min(games.count, max(1, Int((size.width - pad) / (w + pad))))
        for (i, game) in games.prefix(count).enumerated() {
            let r = CGRect(x: pad + CGFloat(i) * (w + pad), y: pad, width: w, height: h)
            let tile = CALayer()
            tile.frame = r
            tile.cornerRadius = 4
            tile.masksToBounds = true
            tile.borderWidth = 1
            tile.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
            tile.contentsGravity = .resizeAspectFill
            if let cover = game.cover, let img = NSImage(contentsOfFile: cover) {
                tile.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            } else {
                // No poster: the game's icon on the theme's panel colour.
                tile.backgroundColor = themeColor(theme.colors.circle).cgColor
                let icon = CALayer()
                let s = min(w, h) * 0.5
                icon.frame = CGRect(x: (w - s) / 2, y: (h - s) / 2 - 8, width: s, height: s)
                icon.contents = IconCache.shared.image(game.icon ?? "sf:gamecontroller.fill", size: s,
                                                       tint: (game.icon ?? "sf:").hasPrefix("sf:") ? accent : nil, scale: scale)
                tile.addSublayer(icon)
            }
            root.addSublayer(tile)
            tiles.append(tile)
            slots.append(r)
            if labelH > 0 {
                let t = text(game.title, size: 12, align: .center)
                t.frame = CGRect(x: r.minX - 4, y: r.maxY + 2, width: r.width + 8, height: labelH)
            }
        }
        if games.isEmpty {
            let t = text("No games found", size: 14, align: .center)
            t.frame = CGRect(x: 0, y: size.height / 2 - 10, width: size.width, height: 20)
        }
    }

    override func click(at point: CGPoint, in screenRect: CGRect) {
        guard let i = slots.firstIndex(where: { $0.contains(point) }) else { return }
        let game = games[i]
        if case .builtin(let b) = game.action, b.hasPrefix("prism:") {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "Prism Launcher", "--args", "--launch", String(b.dropFirst(6))]
            try? p.run()
        } else {
            ActionRunner.run(game.action, builtin: { _ in })
        }
        Log.info("game shelf: launch \(game.title)")
    }

    override func hover(at point: CGPoint?) {
        let i = point.flatMap { p in slots.firstIndex { $0.contains(p) } }
        guard i != hovered else { return }
        hovered = i
        for (j, t) in tiles.enumerated() {
            t.borderColor = (j == i ? accent : NSColor.white.withAlphaComponent(0.5)).cgColor
            t.borderWidth = j == i ? 2 : 1
        }
    }
}

enum WidgetFactory {
    static func make(_ config: WidgetConfig, theme: Theme, accent: NSColor, scale: CGFloat) -> WidgetContent {
        let type: WidgetContent.Type
        switch config.type {
        case "clock": type = ClockContent.self
        case "stat": type = StatContent.self
        case "hpbar": type = HPBarContent.self
        case "text": type = TextContent.self
        case "image": type = ImageContent.self
        case "app": type = AppContent.self
        case "launcher": type = LauncherButtonContent.self
        case "gameshelf": type = GameShelfContent.self
        case "quests": type = QuestContent.self
        default: type = TextContent.self
        }
        return type.init(config: config, theme: theme, accent: accent, scale: scale)
    }
}
