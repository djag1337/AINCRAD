import AppKit

/// A small SAO input box: a title, one text field, and a live line underneath showing what
/// AINCRAD understood (for reminders and events, the date). Return confirms, Esc cancels.
final class SAOPrompt: NSObject, NSTextFieldDelegate {
    static let shared = SAOPrompt()

    private var panel: NSPanel?
    private let field = NSTextField()
    private let preview = NSTextField(labelWithString: "")
    private var kind = ""
    private var onDone: ((String) -> Void)?

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { SAOPrompt.shared.close() }
    }

    /// `kind` "remind" / "event" shows a parsed-date preview; anything else shows none.
    func show(title: String, placeholder: String, kind: String, theme: Theme, onDone: @escaping (String) -> Void) {
        close()
        self.kind = kind
        self.onDone = onDone
        let c = theme.colors
        let width: CGFloat = 520, height: CGFloat = 150
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
        let p = KeyPanel(contentRect: NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.midY + 80, width: width, height: height),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.backgroundColor = themeColor(c.panel).withAlphaComponent(1).cgColor
        root.layer?.cornerRadius = theme.geometry.bubbleRadius
        root.layer?.borderWidth = 1
        root.layer?.borderColor = themeColor(c.panelBorder).cgColor
        let accent = CALayer()
        accent.frame = CGRect(x: 0, y: height - 3, width: width, height: 3)
        accent.backgroundColor = themeColor(c.accent).cgColor
        root.layer?.addSublayer(accent)

        let header = NSTextField(labelWithString: title.uppercased())
        header.font = ThemeFonts.display(theme, 16)
        header.textColor = themeColor(c.panelText)
        header.frame = NSRect(x: 24, y: height - 46, width: width - 48, height: 24)
        root.addSubview(header)

        field.frame = NSRect(x: 24, y: 52, width: width - 48, height: 34)
        field.font = ThemeFonts.body(theme, 20)
        field.placeholderString = placeholder
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = themeColor(c.hover)
        field.textColor = themeColor(c.panelText)
        field.focusRingType = .none
        field.stringValue = ""
        field.delegate = self
        field.wantsLayer = true
        field.layer?.cornerRadius = 4
        root.addSubview(field)

        preview.frame = NSRect(x: 24, y: 18, width: width - 48, height: 22)
        preview.font = ThemeFonts.body(theme, 15)
        preview.textColor = themeColor(c.accent)
        preview.stringValue = "Return to add · Esc to cancel"
        root.addSubview(preview)

        p.contentView = root
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(field)
        panel = p
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        onDone = nil
    }

    func controlTextDidChange(_ obj: Notification) {
        let text = field.stringValue
        guard kind == "remind" || kind == "event", !text.isEmpty else { preview.stringValue = "Return to add · Esc to cancel"; return }
        let p = QuestActions.parse(text)
        let when = p.date == nil ? (kind == "event" ? "next full hour" : "no date") : QuestActions.describe(p)
        preview.stringValue = "“\(p.title)” → \(when)"
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let done = onDone
            close()
            if !text.isEmpty { done?(text) }
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) { close(); return true }
        return false
    }
}
