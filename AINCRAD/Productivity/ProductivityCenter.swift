import AppKit
import ApplicationServices
import UserNotifications

struct ClipboardEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case text, files, image }
    var id = UUID().uuidString
    var kind: Kind
    var title: String
    var value: String
    var created = Date()
    var pinned = false
}

struct QuickCapture: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var text: String
    var kind: ClipboardEntry.Kind = .text
    var created = Date()
}

struct WorkspaceWindow: Codable, Equatable {
    var bundleID: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct WorkspaceLoadout: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var applications: [String]
    var urls: [String] = []
    var windows: [WorkspaceWindow]? = nil
    var created = Date()
}

private struct ProductivityData: Codable {
    var clipboard: [ClipboardEntry] = []
    var captures: [QuickCapture] = []
    var workspaces: [WorkspaceLoadout] = []
    var usage: [String: Int] = [:]
    var excludedBundleIDs: [String] = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.apple.keychainaccess",
        "com.bitwarden.desktop", "com.lastpass.LastPass", "com.dashlane.Dashlane"
    ]
}

/// One local, inspectable store for the daily-use layer. It never sends captured content anywhere.
final class ProductivityCenter {
    private let directory: URL
    private let file: URL
    private var data = ProductivityData()
    private var timer: Timer?
    private var changeCount = NSPasteboard.general.changeCount
    private var activeTimers: [String: (title: String, ends: Date, timer: Timer)] = [:]
    var enabled = true
    var clipboardLimit = 100

    init(directory: URL) {
        self.directory = directory
        file = directory.appendingPathComponent("productivity.json")
        load()
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in self?.pollClipboard() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func load() {
        guard let bytes = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode(ProductivityData.self, from: bytes) else { return }
        data = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
            let d = try e.encode(data)
            try d.write(to: file, options: .atomic)
        } catch { Log.error("productivity store: \(error.localizedDescription)") }
    }

    private func pollClipboard() {
        guard enabled else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }
        changeCount = pb.changeCount
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        guard !data.excludedBundleIDs.contains(frontID) else { return }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            addClipboard(kind: .files, title: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files", value: urls.map(\.path).joined(separator: "\n"))
        } else if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let oneLine = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            addClipboard(kind: .text, title: String(oneLine.prefix(72)), value: text)
        } else if let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation, tiff.count < 8_000_000 {
            addClipboard(kind: .image, title: "Image \(Int(image.size.width))×\(Int(image.size.height))", value: tiff.base64EncodedString())
        }
    }

    private func addClipboard(kind: ClipboardEntry.Kind, title: String, value: String) {
        if let first = data.clipboard.first, first.kind == kind && first.value == value { return }
        data.clipboard.insert(ClipboardEntry(kind: kind, title: title, value: value), at: 0)
        let pins = data.clipboard.filter(\.pinned)
        let regular = data.clipboard.filter { !$0.pinned }.prefix(max(1, clipboardLimit))
        data.clipboard = pins + regular
        save()
    }

    func clipboardMenu(query: String? = nil) -> [MenuItem] {
        let q = query?.lowercased() ?? ""
        return data.clipboard.filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.value.lowercased().contains(q) }.prefix(30).map { e in
            let symbol = e.pinned ? "pin.fill" : (e.kind == .files ? "doc.on.doc.fill" : e.kind == .image ? "photo.fill" : "doc.text.fill")
            return MenuItem(id: "clipboard:\(e.id)", name: e.title, icon: "sf:\(symbol)", action: .builtin("productivity:paste:\(e.id)"), description: "\(e.kind.rawValue.capitalized) · \(e.created.formatted(date: .abbreviated, time: .shortened))")
        }
    }

    func paste(_ id: String) {
        guard let e = data.clipboard.first(where: { $0.id == id }) else { return }
        let pb = NSPasteboard.general; pb.clearContents()
        switch e.kind {
        case .text: pb.setString(e.value, forType: .string)
        case .files:
            let urls = e.value.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            pb.writeObjects(urls as [NSURL])
        case .image:
            if let d = Data(base64Encoded: e.value), let image = NSImage(data: d) { pb.writeObjects([image]) }
        }
        changeCount = pb.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard AXIsProcessTrusted() else { NSSound.beep(); return }
            let src = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
            down?.flags = .maskCommand
            let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
        record("clipboard:\(id)")
    }

    func togglePin(_ id: String) {
        guard let i = data.clipboard.firstIndex(where: { $0.id == id }) else { return }
        data.clipboard[i].pinned.toggle(); save()
    }

    func clearClipboardHistory() { data.clipboard.removeAll { !$0.pinned }; save() }

    func capture(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        data.captures.insert(QuickCapture(text: clean), at: 0)
        if data.captures.count > 200 { data.captures.removeLast(data.captures.count - 200) }
        save()
    }

    func captureClipboard() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            data.captures.insert(QuickCapture(text: urls.map(\.path).joined(separator: "\n"), kind: .files), at: 0); save()
        } else if let s = pb.string(forType: .string) { capture(s) }
        else if let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation, tiff.count < 8_000_000 {
            data.captures.insert(QuickCapture(text: tiff.base64EncodedString(), kind: .image), at: 0); save()
        } else { NSSound.beep() }
    }

    private func selectedText() -> String? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success else { return nil }
        return (selected as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func contextMenu() -> [MenuItem] {
        var out: [MenuItem] = []
        if let text = selectedText(), !text.isEmpty {
            let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            out += [
                MenuItem(name: "Copy Selection", icon: "sf:doc.on.doc.fill", action: .builtin("productivity:context:copy:\(encoded)")),
                MenuItem(name: "Capture Selection", icon: "sf:tray.and.arrow.down.fill", action: .builtin("productivity:captureText:\(encoded)")),
                MenuItem(name: "Search Selection", icon: "sf:magnifyingglass", action: .url("https://www.google.com/search?q=\(encoded)")),
                MenuItem(name: "Uppercase", icon: "sf:textformat", action: .builtin("productivity:context:uppercase:\(encoded)")),
                MenuItem(name: "Lowercase", icon: "sf:textformat", action: .builtin("productivity:context:lowercase:\(encoded)"))
            ]
        }
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            out.append(MenuItem(name: "Quit \(front.localizedName ?? "Current App")", icon: "sf:xmark.circle.fill", action: .builtin("productivity:quitFront")))
        }
        if out.isEmpty { out.append(MenuItem(name: "No selection detected", icon: "sf:cursorarrow.rays")) }
        return out
    }

    func putTextOnClipboard(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        changeCount = NSPasteboard.general.changeCount
    }

    func captureMenu() -> [MenuItem] {
        data.captures.prefix(30).map { c in
            let title = c.kind == .image ? "Captured image" : String(c.text.replacingOccurrences(of: "\n", with: " ").prefix(72))
            return MenuItem(id: "capture:\(c.id)", name: title, icon: "sf:\(c.kind == .files ? "doc.on.doc.fill" : c.kind == .image ? "photo.fill" : "tray.full.fill")", action: .builtin("productivity:copyCapture:\(c.id)"), description: c.created.formatted(date: .abbreviated, time: .shortened))
        }
    }

    func copyCapture(_ id: String) {
        guard let c = data.captures.first(where: { $0.id == id }) else { return }
        let pb = NSPasteboard.general; pb.clearContents()
        switch c.kind {
        case .text: pb.setString(c.text, forType: .string)
        case .files: pb.writeObjects(c.text.split(separator: "\n").map { NSURL(fileURLWithPath: String($0)) })
        case .image:
            if let d = Data(base64Encoded: c.text), let image = NSImage(data: d) { pb.writeObjects([image]) }
        }
        changeCount = NSPasteboard.general.changeCount
    }

    func saveWorkspace(named raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }.compactMap(\.bundleIdentifier)
        let windows = captureWindows(for: Set(apps))
        let value = WorkspaceLoadout(name: name, applications: Array(Set(apps)).sorted(), windows: windows)
        data.workspaces.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        data.workspaces.insert(value, at: 0); save()
    }

    func workspacesMenu() -> [MenuItem] {
        var out = [MenuItem(id: "workspace:capture", name: "Save Current Apps as Workspace…", icon: "sf:plus.rectangle.on.rectangle", action: .builtin("productivity:newWorkspace"))]
        out += data.workspaces.map { w in MenuItem(id: "workspace:\(w.id)", name: w.name, icon: "sf:rectangle.3.group.fill", action: .builtin("productivity:workspace:\(w.id)"), description: "Opens \(w.applications.count) apps") }
        return out
    }

    func runWorkspace(_ id: String) {
        guard let w = data.workspaces.first(where: { $0.id == id }) else { return }
        for bundleID in w.applications {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { continue }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
        for s in w.urls { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }
        if let windows = w.windows, !windows.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.restoreWindows(windows) }
        }
        record("workspace:\(id)")
    }

    private func captureWindows(for bundleIDs: Set<String>) -> [WorkspaceWindow] {
        guard AXIsProcessTrusted() else { return [] }
        var result: [WorkspaceWindow] = []
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier.map(bundleIDs.contains) == true {
            guard let id = app.bundleIdentifier else { continue }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &raw) == .success, let wins = raw as? [AXUIElement] else { continue }
            for win in wins {
                var pRaw: CFTypeRef?, sRaw: CFTypeRef?
                guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &pRaw) == .success,
                      AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sRaw) == .success,
                      let pRaw, let sRaw else { continue }
                var p = CGPoint.zero, s = CGSize.zero
                guard AXValueGetValue(pRaw as! AXValue, .cgPoint, &p), AXValueGetValue(sRaw as! AXValue, .cgSize, &s), s.width > 100, s.height > 80 else { continue }
                result.append(WorkspaceWindow(bundleID: id, x: p.x, y: p.y, width: s.width, height: s.height))
            }
        }
        return result
    }

    private func restoreWindows(_ saved: [WorkspaceWindow]) {
        guard AXIsProcessTrusted() else { return }
        for group in Dictionary(grouping: saved, by: \.bundleID) {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: group.key).first else { continue }
            let ax = AXUIElementCreateApplication(app.processIdentifier); var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &raw) == .success, let wins = raw as? [AXUIElement] else { continue }
            for (win, spec) in zip(wins, group.value) {
                var p = CGPoint(x: spec.x, y: spec.y), s = CGSize(width: spec.width, height: spec.height)
                if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
                if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, v) }
            }
        }
    }

    func startTimer(minutes: Int, title: String = "AINCRAD Timer") {
        let mins = min(max(minutes, 1), 24 * 60)
        let id = UUID().uuidString, end = Date().addingTimeInterval(Double(mins * 60))
        let t = Timer.scheduledTimer(withTimeInterval: Double(mins * 60), repeats: false) { [weak self] _ in
            self?.activeTimers[id] = nil
            let content = UNMutableNotificationContent(); content.title = title; content.body = "\(mins)-minute timer complete"; content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
        activeTimers[id] = (title, end, t)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var timerSummary: String? {
        activeTimers.values.sorted { $0.ends < $1.ends }.first.map { "\($0.title) · \(max(0, Int($0.ends.timeIntervalSinceNow / 60) + 1))m" }
    }

    var latestClipboardTitle: String? { data.clipboard.first?.title }

    func systemMenu() -> [MenuItem] {
        [
            MenuItem(name: "Tile Window Left", icon: "sf:rectangle.lefthalf.inset.filled", action: .builtin("productivity:window:left")),
            MenuItem(name: "Tile Window Right", icon: "sf:rectangle.righthalf.inset.filled", action: .builtin("productivity:window:right")),
            MenuItem(name: "Maximize Window", icon: "sf:rectangle.inset.filled", action: .builtin("productivity:window:max")),
            MenuItem(name: "Sound Settings", icon: "sf:speaker.wave.2.fill", action: .url("x-apple.systempreferences:com.apple.Sound-Settings.extension")),
            MenuItem(name: "Volume Up", icon: "sf:speaker.plus.fill", action: .builtin("productivity:volume:up")),
            MenuItem(name: "Volume Down", icon: "sf:speaker.minus.fill", action: .builtin("productivity:volume:down")),
            MenuItem(name: "Mute / Unmute", icon: "sf:speaker.slash.fill", action: .builtin("productivity:volume:toggle")),
            MenuItem(name: "Bluetooth Settings", icon: "sf:dot.radiowaves.left.and.right", action: .url("x-apple.systempreferences:com.apple.BluetoothSettings")),
            MenuItem(name: "Lock Screen", icon: "sf:lock.fill", action: .builtin("productivity:lock"))
        ]
    }

    func tileFrontWindow(_ mode: String) {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { NSSound.beep(); return }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var raw: CFTypeRef?; guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &raw) == .success, let raw else { return }
        let win = raw as! AXUIElement
        let screen = NSScreen.main?.visibleFrame ?? .zero
        var frame: CGRect
        switch mode { case "left": frame = CGRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height); case "right": frame = CGRect(x: screen.midX, y: screen.minY, width: screen.width / 2, height: screen.height); default: frame = screen }
        var pos = CGPoint(x: frame.minX, y: NSScreen.screens.first!.frame.height - frame.maxY)
        var size = frame.size
        if let p = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, p) }
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, s) }
    }

    func record(_ key: String) { data.usage[key, default: 0] += 1; save() }

    func suggestions() -> [MenuItem] {
        let ranked = data.usage.sorted { $0.value > $1.value }.prefix(6)
        return ranked.compactMap { key, count in
            if key.hasPrefix("workspace:"), let w = data.workspaces.first(where: { "workspace:\($0.id)" == key }) {
                return MenuItem(name: w.name, icon: "sf:sparkles", action: .builtin("productivity:\(key)"), description: "Suggested from \(count) uses")
            }
            if key.hasPrefix("clipboard:"), let e = data.clipboard.first(where: { "clipboard:\($0.id)" == key }) {
                return MenuItem(name: e.title, icon: "sf:sparkles", action: .builtin("productivity:paste:\(e.id)"), description: "Frequently used clipboard item")
            }
            return nil
        }
    }

    func rootMenu() -> MenuItem {
        MenuItem(id: "aincrad:command-center", name: "Command Center", icon: "sf:command.circle.fill", children: [
            MenuItem(name: "Suggested", icon: "sf:sparkles", provider: "productivity:suggestions"),
            MenuItem(name: "Current Context", icon: "sf:cursorarrow.rays", provider: "productivity:context"),
            MenuItem(name: "Clipboard", icon: "sf:clipboard.fill", provider: "productivity:clipboard"),
            MenuItem(name: "Quick Capture", icon: "sf:tray.full.fill", children: [
                MenuItem(name: "Capture Current Clipboard", icon: "sf:plus", action: .builtin("productivity:captureClipboard")),
                MenuItem(name: "Inbox", icon: "sf:tray.full.fill", provider: "productivity:captures")
            ]),
            MenuItem(name: "Workspaces", icon: "sf:rectangle.3.group.fill", provider: "productivity:workspaces"),
            MenuItem(name: "Window & System", icon: "sf:macwindow", provider: "productivity:system"),
            MenuItem(name: "Extensions", icon: "sf:puzzlepiece.extension.fill", provider: "ext:all")
        ])
    }

    func commandResults(_ raw: String) -> [MenuItem] {
        let q = raw.trimmingCharacters(in: .whitespaces)
        let lower = q.lowercased()
        if lower.hasPrefix("note ") || lower.hasPrefix("capture ") {
            let text = String(q.dropFirst(q.firstIndex(of: " ")!.utf16Offset(in: q) + 1))
            return [MenuItem(id: "command:capture", name: "Capture “\(String(text.prefix(55)))”", icon: "sf:tray.and.arrow.down.fill", action: .builtin("productivity:captureText:\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text)"))]
        }
        if lower.hasPrefix("timer "), let mins = Int(lower.split(separator: " ").dropFirst().first ?? "") {
            return [MenuItem(id: "command:timer", name: "Start a \(mins)-minute timer", icon: "sf:timer", action: .builtin("productivity:timer:\(mins)"))]
        }
        if lower.hasPrefix("paste ") { return clipboardMenu(query: String(q.dropFirst(6))) }
        if lower.hasPrefix("workspace ") {
            let term = String(lower.dropFirst(10))
            return data.workspaces.filter { $0.name.lowercased().contains(term) }.map { MenuItem(name: "Open \($0.name)", icon: "sf:rectangle.3.group.fill", action: .builtin("productivity:workspace:\($0.id)")) }
        }
        if lower == "window left" || lower == "window right" || lower == "window max" {
            let mode = String(lower.split(separator: " ").last!); return [MenuItem(name: "Move active window: \(mode)", icon: "sf:macwindow", action: .builtin("productivity:window:\(mode)"))]
        }
        return []
    }
}
