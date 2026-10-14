import AppKit
import CoreImage

/// A white macOS folder with a thin outline in the theme's accent, for dock folders set to follow
/// the theme. The same image is drawn in the SAO dock and written as the folder's Finder icon.
enum ThemedFolderIcon {
    private static var cache: [String: NSImage] = [:]

    /// `ring` is the outline's width as a fraction of the size: ~3% reads well at Finder sizes;
    /// small renders (the dock draws it at 32 px on a 1x display) need a bolder ring.
    static func make(accentHex: String, size: Int = 1024, ring: Double = 1.0 / 34) -> NSImage? {
        let key = "\(accentHex)|\(size)|\(ring)"
        if let hit = cache[key] { return hit }
        let base = NSWorkspace.shared.icon(for: .folder)
        base.size = NSSize(width: size, height: size)
        var rect = NSRect(x: 0, y: 0, width: size, height: size)
        guard let cg = base.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let folder = CIImage(cgImage: cg)
        // White: drop the blue, then lift towards white keeping the folder's own shading.
        let white = folder
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.45, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.45, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.47, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0.55, y: 0.55, z: 0.56, w: 0)])
        // Outline: the folder's shape, grown a little and filled with the accent, behind it.
        let accent = CIColor(color: themeColor(accentHex)) ?? CIColor(red: 0.93, green: 0.49, blue: 0.72)
        // The icon's edge is a soft shadow, so make the shape solid first (alpha > ~0.4 → 1),
        // or the grown outline comes out as a faint haze.
        let solid = folder
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 6), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: -2.4)])
            .applyingFilter("CIColorClamp")
        let radius = Double(size) * ring
        let grown = solid.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
        let shape = grown.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: linear(accent.red), y: linear(accent.green), z: linear(accent.blue), w: 0)])
            .applyingFilter("CIPremultiply")
        // Trim the white folder to its solid shape, so its soft shadow doesn't wash the ring out.
        let trimmed = white.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: solid])
        let composed = trimmed.composited(over: shape).cropped(to: folder.extent)
        guard let out = CIContext().createCGImage(composed, from: folder.extent) else { return nil }
        let image = NSImage(cgImage: out, size: NSSize(width: size, height: size))
        cache[key] = image
        return image
    }

    /// Core Image works in linear light; the accent is sRGB, so convert it or it comes out pale.
    private static func linear(_ c: CGFloat) -> CGFloat {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Writes the themed icon as the folder's Finder icon. Returns false if macOS refused.
    @discardableResult
    static func apply(to folder: URL, accentHex: String) -> Bool {
        guard let image = make(accentHex: accentHex) else { return false }
        let ok = NSWorkspace.shared.setIcon(image, forFile: folder.path, options: [])
        Log.info("dock: themed icon \(accentHex) on \(folder.lastPathComponent): \(ok)")
        return ok
    }
}
