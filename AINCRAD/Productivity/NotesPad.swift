import AppKit

/// Quick notes: Markdown files in ~/AINCRAD Notes (home, so no folder-access prompt), written in
/// an SAO-styled notepad window. The first line is the title. Typing saves after a second.
final class NotesPad: NSObject, NSTextViewDelegate, NSWindowDelegate {
    static let shared = NotesPad()
    static var folder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AINCRAD Notes", isDirectory: true) }

    private var window: NSWindow?
    private var textView: NSTextView?
    private var file: URL?
    private var saveWork: DispatchWorkItem?

    // MARK: Files

    struct Note { let url: URL; let title: String; let modified: Date }

    static func notes() -> [Note] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension == "md" }.map { url in
            let firstLine = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").first.map(String.init) ?? ""
            let title = firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
            let date = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            return Note(url: url, title: title.isEmpty ? url.deletingPathExtension().lastPathComponent : title, modified: date)
        }.sorted { $0.modified > $1.modified }
    }

    private static func newFileURL() -> URL {
        let stamp = Date().formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)",
                                               timeZone: .current, calendar: .current))
        var url = folder.appendingPathComponent("Note \(stamp).md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("Note \(stamp) \(n).md"); n += 1
        }
        return url
    }

    // MARK: Launcher

    /// Command Center › Notes.
    static func menuItems() -> [MenuItem] {
        var out = [MenuItem(id: "notes:new", name: "New Note", icon: "sf:square.and.pencil", action: .builtin("notes:new"),
                            description: "Opens a fresh note. It saves as you type, to ~/AINCRAD Notes.")]
        for note in notes().prefix(20) {
            out.append(MenuItem(id: "note:" + note.url.lastPathComponent, name: note.title, icon: "sf:note.text",
                                action: .builtin("notes:open:" + (note.url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")),
                                description: "Edited " + note.modified.formatted(.relative(presentation: .named))))
        }
        out.append(MenuItem(id: "notes:folder", name: "Show Notes Folder", icon: "sf:folder", action: .builtin("notes:folder")))
        return out
    }

    func perform(_ builtin: String, theme: Theme) {
        let parts = builtin.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return }
        try? FileManager.default.createDirectory(at: NotesPad.folder, withIntermediateDirectories: true)
        switch parts[1] {
        case "new": open(nil, theme: theme)
        case "open":
            let name = parts.count > 2 ? (parts[2].removingPercentEncoding ?? parts[2]) : ""
            open(NotesPad.folder.appendingPathComponent(name), theme: theme)
        case "folder": NSWorkspace.shared.open(NotesPad.folder)
        default: break
        }
    }

    // MARK: Window

    func open(_ url: URL?, theme: Theme) {
        saveNow()
        let c = theme.colors
        let w = window ?? makeWindow()
        file = url
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        w.backgroundColor = themeColor(c.panel)
        // Title bar text follows the window's appearance; match the theme, not macOS dark mode.
        let panel = themeColor(c.panel).usingColorSpace(.sRGB) ?? .white
        let luminance = 0.299 * panel.redComponent + 0.587 * panel.greenComponent + 0.114 * panel.blueComponent
        w.appearance = NSAppearance(named: luminance > 0.5 ? .aqua : .darkAqua)
        w.contentView?.layer?.backgroundColor = themeColor(c.panel).cgColor
        if let tv = textView {
            tv.string = text
            tv.font = ThemeFonts.body(theme, 18)
            tv.textColor = themeColor(c.panelText)
            tv.insertionPointColor = themeColor(c.accent)
            tv.backgroundColor = themeColor(c.panel)
            tv.selectedTextAttributes = [.backgroundColor: themeColor(c.accent).withAlphaComponent(0.3)]
            tv.typingAttributes = [.font: ThemeFonts.body(theme, 18), .foregroundColor: themeColor(c.panelText)]
        }
        w.title = url == nil ? "New Note" : (NotesPad.notes().first { $0.url == url }?.title ?? "Note")
        if let accent = w.contentView?.layer?.sublayers?.first(where: { $0.name == "accent" }) {
            accent.backgroundColor = themeColor(c.accent).cgColor
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(textView)
        if text.isEmpty { textView?.string = "" }
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 360, height: 240)
        w.center()
        w.setFrameAutosaveName("AINCRADNotesPad")
        w.delegate = self
        let root = NSView(frame: w.contentLayoutRect)
        root.wantsLayer = true
        let accent = CALayer()
        accent.name = "accent"
        accent.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
        accent.frame = CGRect(x: 0, y: root.bounds.height - 30, width: root.bounds.width, height: 2)
        root.layer?.addSublayer(accent)
        let scroll = NSScrollView(frame: root.bounds.insetBy(dx: 18, dy: 18).offsetBy(dx: 0, dy: -12))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let tv = NSTextView(frame: scroll.bounds)
        tv.autoresizingMask = [.width]
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 4, height: 8)
        tv.delegate = self
        scroll.documentView = tv
        root.addSubview(scroll)
        w.contentView = root
        window = w
        textView = tv
        return w
    }

    func textDidChange(_ notification: Notification) {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        if let first = textView?.string.split(separator: "\n").first {
            window?.title = String(first).trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
        }
    }

    private func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        guard let text = textView?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let url = file ?? NotesPad.newFileURL()
        do {
            try FileManager.default.createDirectory(at: NotesPad.folder, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            if file == nil {
                file = url
                BattleLog.shared.add("Note saved", symbol: "note.text")
            }
        } catch {
            Log.error("notes: couldn't save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func windowWillClose(_ notification: Notification) { saveNow() }
}
