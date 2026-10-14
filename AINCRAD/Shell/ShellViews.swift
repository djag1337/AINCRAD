import AppKit

struct ShellApp: Equatable {
    var name: String
    var url: URL
    var bundleID: String?
    var pinned: Bool
    /// A folder (Downloads and so on): clicking shows its newest files instead of launching.
    var folder = false
    /// Drawn as a white folder outlined in the theme accent.
    var themedIcon = false
}

/// A borderless panel above the launcher that never takes key status, so clicking the shell
/// doesn't close the launcher underneath it.
final class ShellPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Layer-hosting, top-left-origin view; subclasses lay out CALayers directly.
class ShellLayerView: NSView {
    let host = CALayer()
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        host.isGeometryFlipped = true
        layer = host
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func text(_ s: String, _ font: NSFont, _ color: NSColor, align: CATextLayerAlignmentMode = .left) -> CATextLayer {
        let t = CATextLayer()
        t.string = s
        t.font = font
        t.fontSize = font.pointSize
        t.foregroundColor = color.cgColor
        t.alignmentMode = align
        t.truncationMode = .end
        t.contentsScale = window?.backingScaleFactor ?? 2
        return t
    }
}
