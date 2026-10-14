import CoreGraphics

/// Pure geometry so it can be unit-tested. Coordinates are top-left origin (flipped).
enum MenuLayout {
    /// Centre of the root column, kept fully on screen with room for the caption on its left.
    static func anchor(cursor: CGPoint, bounds: CGRect, rootSize: CGSize, leftReserve: CGFloat, margin: CGFloat) -> CGPoint {
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { lo > hi ? (lo + hi) / 2 : min(max(v, lo), hi) }
        return CGPoint(
            x: clamp(cursor.x, bounds.minX + margin + leftReserve + rootSize.width / 2, bounds.maxX - margin - rootSize.width / 2),
            y: clamp(cursor.y, bounds.minY + margin + rootSize.height / 2, bounds.maxY - margin - rootSize.height / 2))
    }

    /// Leftward shift (<= 0) that brings the right edge on screen without pushing the left edge off.
    static func horizontalShift(leftEdge: CGFloat, rightEdge: CGFloat, bounds: CGRect, margin: CGFloat) -> CGFloat {
        let overflow = rightEdge - (bounds.maxX - margin)
        guard overflow > 0 else { return 0 }
        let room = leftEdge - (bounds.minX + margin)
        return -min(overflow, max(room, 0))
    }

    /// Rows near the edge of the visible window fade instead of cutting off.
    static func rowOpacity(distance: Int, visibleRows: Int) -> Float {
        let d = abs(distance)
        if d <= visibleRows - 2 { return 1 }
        if d == visibleRows - 1 { return 0.55 }
        if d == visibleRows { return 0.22 }
        return 0
    }
}
