import AppKit

/// Rasterised icons keyed by spec + size + tint, so reopening the launcher doesn't touch the disk.
final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, CGImage>()

    init() { cache.countLimit = 400 }

    /// `tint` only applies to SF Symbols; file/app icons keep their own colours.
    func image(_ spec: String, size: CGFloat, tint: NSColor?, scale: CGFloat) -> CGImage? {
        let key = "\(spec)|\(size)|\(tint?.description ?? "-")|\(scale)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = load(spec, size: size), let img = rasterize(source, size: size, scale: scale,
                                                                       tint: IconCache.isSymbol(spec) ? tint : nil) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    static func isSymbol(_ spec: String) -> Bool { spec.hasPrefix("sf:") }

    /// Icon spec used when an item doesn't name one.
    static func defaultSpec(for item: MenuItem) -> String {
        if let icon = item.icon { return icon }
        switch item.action {
        case .app(let t): return ActionRunner.appURL(t).map { "app:" + $0.path } ?? "sf:app.fill"
        case .open(let p): return "file:" + p
        case .url: return "sf:globe"
        case .builtin: return "sf:gearshape.fill"
        case .shortcut: return "sf:square.2.layers.3d.fill"
        case .shell: return "sf:terminal.fill"
        case nil: return item.hasSubmenu ? "sf:folder.fill" : "sf:circle"
        }
    }

    private func load(_ spec: String, size: CGFloat) -> NSImage? {
        if spec.hasPrefix("sf:") {
            guard let base = NSImage(systemSymbolName: String(spec.dropFirst(3)), accessibilityDescription: nil) else { return nil }
            return base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)) ?? base
        }
        // Drawn small (dock buttons), so a bolder ring: about 2 px at 32 px.
        if spec.hasPrefix("themedfolder:") { return ThemedFolderIcon.make(accentHex: String(spec.dropFirst(13)), size: 128, ring: 1.0 / 16) }
        let path: String
        if let colon = spec.firstIndex(of: ":"), ["app", "file", "image"].contains(String(spec[..<colon])) {
            path = String(spec[spec.index(after: colon)...])
        } else {
            path = spec
        }
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        if spec.hasPrefix("image:") { return NSImage(contentsOfFile: expanded) }
        return NSWorkspace.shared.icon(forFile: expanded)
    }

    /// With `tint`, the image is drawn as a monochrome mask and filled, which keeps the cut-outs
    /// of multi-layer symbols (a palette colour would paint every layer the same and hide them).
    private func rasterize(_ image: NSImage, size: CGFloat, scale: CGFloat, tint: NSColor?) -> CGImage? {
        let px = max(1, Int(ceil(size * scale)))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let s = image.size
        let k = min(CGFloat(px) / max(s.width, 1), CGFloat(px) / max(s.height, 1))
        let w = s.width * k, h = s.height * k
        image.draw(in: NSRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(px) - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        if let tint {
            ctx.setBlendMode(.sourceIn)
            ctx.setFillColor(tint.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
        }
        return ctx.makeImage()
    }
}
