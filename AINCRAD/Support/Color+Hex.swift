import AppKit

extension NSColor {
    /// "#RRGGBB" or "#RRGGBBAA".
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let full = s.count == 6 ? (v << 8) | 0xFF : v
        self.init(srgbRed: CGFloat((full >> 24) & 0xFF) / 255,
                  green: CGFloat((full >> 16) & 0xFF) / 255,
                  blue: CGFloat((full >> 8) & 0xFF) / 255,
                  alpha: CGFloat(full & 0xFF) / 255)
    }
}

/// Theme colors fall back to magenta so a typo is obvious on screen instead of silently invisible.
func themeColor(_ hex: String) -> NSColor {
    NSColor(hex: hex) ?? .magenta
}
