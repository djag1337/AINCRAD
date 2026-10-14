import AppKit
import Carbon.HIToolbox

/// Borderless panel just above the desktop icons: below every app window, on all Spaces,
/// never in Mission Control or ⌘-Tab. Click-through unless the widget is interactive or editing.
final class WidgetPanel: NSPanel {
    var allowsKey = false

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

protocol WidgetHostDelegate: AnyObject {
    func widgetSelected(_ id: String)
    func widgetBeginChange(_ id: String)
    func widgetLiveChange(_ id: String, _ change: (inout WidgetConfig) -> Void)
    func widgetDelete(_ id: String)
    func widgetOpenLauncher(at screenRect: CGRect)
}

/// Hosts one widget's layers, rotated about its centre, plus the editing chrome
/// (outline, resize handle, rotation knob) that rotates with it.
final class WidgetHostView: NSView {
    weak var delegate: WidgetHostDelegate?
    private(set) var config: WidgetConfig
    private let holder = CALayer()
    private let outline = CAShapeLayer()
    private let resize = CALayer()
    private let knob = CALayer()
    private let knobLine = CALayer()
    /// "HUD" tag shown in edit mode, so HUD widgets stand out from desktop ones.
    private(set) var hudTag = CATextLayer()
    private var content: WidgetContent?
    private var editing = false
    private var selected = false
    private var tracking: NSTrackingArea?

    private enum Drag { case move, resize, rotate }
    private var drag: Drag?
    private var dragStartMouse = NSPoint.zero
    private var dragStart: WidgetConfig?

    static let margin: CGFloat = 14
    static let editMargin: CGFloat = 34

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { editing }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(config: WidgetConfig) {
        self.config = config
        super.init(frame: .zero)
        let host = CALayer()
        host.isGeometryFlipped = true
        layer = host
        wantsLayer = true
        host.addSublayer(holder)
        outline.fillColor = nil
        outline.lineWidth = 1.5
        outline.lineDashPattern = [6, 4]
        resize.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
        resize.borderWidth = 1.5
        resize.backgroundColor = NSColor.white.cgColor
        knob.bounds = CGRect(x: 0, y: 0, width: 14, height: 14)
        knob.cornerRadius = 7
        knob.borderWidth = 1.5
        knob.backgroundColor = NSColor.white.cgColor
        hudTag.string = "HUD"
        hudTag.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        hudTag.fontSize = 10
        hudTag.alignmentMode = .center
        hudTag.foregroundColor = NSColor.white.cgColor
        hudTag.cornerRadius = 3
        hudTag.contentsScale = 2
        [outline, knobLine, resize, knob, hudTag].forEach { holder.addSublayer($0) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func install(_ content: WidgetContent) {
        self.content?.stop()
        self.content?.root.removeFromSuperlayer()
        self.content = content
        Motion.instant { holder.insertSublayer(content.root, at: 0) }
        layoutHolder()
    }

    func apply(config: WidgetConfig, editing: Bool, selected: Bool) {
        self.config = config
        self.editing = editing
        self.selected = selected
        layoutHolder()
    }

    var widgetContent: WidgetContent? { content }

    private func layoutHolder() {
        let w = config.width, h = config.height
        Motion.instant {
            holder.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            holder.position = CGPoint(x: bounds.midX, y: bounds.midY)
            holder.transform = CATransform3DMakeRotation(CGFloat(config.rotation * .pi / 180), 0, 0, 1)
            content?.root.position = CGPoint(x: w / 2, y: h / 2)
            let accent = content?.accent ?? .systemOrange
            outline.path = CGPath(rect: CGRect(x: -3, y: -3, width: w + 6, height: h + 6), transform: nil)
            outline.strokeColor = (selected ? accent : NSColor.white.withAlphaComponent(0.6)).cgColor
            resize.position = CGPoint(x: w + 3, y: h + 3)
            resize.borderColor = accent.cgColor
            knob.position = CGPoint(x: w / 2, y: -24)
            knob.borderColor = accent.cgColor
            knobLine.frame = CGRect(x: w / 2 - 0.75, y: -17, width: 1.5, height: 14)
            knobLine.backgroundColor = accent.cgColor
            outline.isHidden = !editing
            hudTag.isHidden = !(editing && config.hud)
            hudTag.frame = CGRect(x: -3, y: -20, width: 34, height: 15)
            hudTag.backgroundColor = accent.cgColor
            hudTag.contentsScale = window?.backingScaleFactor ?? 2
            [resize, knob, knobLine].forEach { $0.isHidden = !(editing && selected && !config.locked) }
        }
    }

    override func layout() {
        super.layout()
        layoutHolder()
    }

    // MARK: Editing

    /// Mouse point in the widget's own (unrotated) coordinates.
    private func local(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let a = CGFloat(-config.rotation * .pi / 180)
        let c = cos(a), s = sin(a)
        let dx: CGFloat = p.x - bounds.midX, dy: CGFloat = p.y - bounds.midY
        let x: CGFloat = dx * c - dy * s + CGFloat(config.width) / 2
        let y: CGFloat = dx * s + dy * c + CGFloat(config.height) / 2
        return CGPoint(x: x, y: y)
    }

    override func mouseDown(with event: NSEvent) {
        guard editing else { return }
        delegate?.widgetSelected(config.id)
        window?.makeKey()
        window?.makeFirstResponder(self)
        guard !config.locked else { return }
        let p = local(event)
        if hypot(p.x - config.width / 2, p.y + 24) < 12 { drag = .rotate }
        else if abs(p.x - config.width - 3) < 12 && abs(p.y - config.height - 3) < 12 { drag = .resize }
        else { drag = .move }
        dragStartMouse = NSEvent.mouseLocation
        dragStart = config
        delegate?.widgetBeginChange(config.id)
    }

    override func mouseDragged(with event: NSEvent) {
        guard editing, let drag, let start = dragStart else { return }
        let m = NSEvent.mouseLocation
        let dx = Double(m.x - dragStartMouse.x), dy = Double(dragStartMouse.y - m.y) // to top-left-origin
        let shift = event.modifierFlags.contains(.shift)
        delegate?.widgetLiveChange(config.id) { c in
            switch drag {
            case .move:
                c.x = (start.x + dx).rounded()
                c.y = (start.y + dy).rounded()
                if shift { c.x = (c.x / 10).rounded() * 10; c.y = (c.y / 10).rounded() * 10 }
            case .resize:
                let a: Double = -start.rotation * .pi / 180
                let lx: Double = dx * cos(a) - dy * sin(a)
                let ly: Double = dx * sin(a) + dy * cos(a)
                c.width = max(40, (start.width + lx).rounded())
                c.height = max(30, (start.height + ly).rounded())
            case .rotate:
                guard let w = window else { return }
                let center = NSPoint(x: w.frame.midX, y: w.frame.midY)
                var deg = Double(atan2(m.x - center.x, m.y - center.y)) * 180 / .pi
                if shift { deg = (deg / 15).rounded() * 15 }
                c.rotation = ((deg + 360).truncatingRemainder(dividingBy: 360)).rounded()
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if editing {
            drag = nil
            dragStart = nil
        } else if config.isInteractive, let w = window, bounds.contains(convert(event.locationInWindow, from: nil)) {
            content?.click(at: local(event), in: w.frame)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard editing, selected else { return super.keyDown(with: event) }
        let step: Double = event.modifierFlags.contains(.shift) ? 10 : 1
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            delegate?.widgetDelete(config.id)
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            guard !config.locked else { return }
            delegate?.widgetBeginChange(config.id)
            delegate?.widgetLiveChange(config.id) { c in
                switch Int(event.keyCode) {
                case kVK_LeftArrow: c.x -= step
                case kVK_RightArrow: c.x += step
                case kVK_UpArrow: c.y -= step
                default: c.y += step
                }
            }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: Hover for interactive widgets

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { if !editing { content?.setHover(true) } }
    override func mouseExited(with event: NSEvent) {
        content?.setHover(false)
        content?.hover(at: nil)
    }
    override func mouseMoved(with event: NSEvent) { if !editing { content?.hover(at: local(event)) } }
}
