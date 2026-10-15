import AppKit

/// The launcher's Files circle: recent files, the newest downloads, mounted drives and the Trash.
/// Lists come from Spotlight (no folder-access prompts), read off the main thread.
final class FilesMenu {
    static let shared = FilesMenu()
    var onUpdate: ((String) -> Void)?
    private var lists: [String: (time: Date, urls: [URL])] = [:]
    private var loading = Set<String>()

    static func root() -> MenuItem {
        MenuItem(id: "files:root", name: "Files", icon: "sf:doc.on.doc.fill", children: [
            MenuItem(id: "files:recent", name: "Recent Files", icon: "sf:clock.arrow.circlepath", provider: "files:recent",
                     description: "Files you've opened in the last week."),
            MenuItem(id: "files:downloads", name: "Downloads", icon: "sf:arrow.down.circle.fill", provider: "files:downloads",
                     description: "Your newest downloads."),
            MenuItem(id: "files:drives", name: "Drives", icon: "sf:externaldrive.fill", provider: "files:drives",
                     description: "Mounted disks, with free space. Eject removable ones here."),
            MenuItem(id: "files:trash", name: "Trash", icon: "sf:trash.fill", provider: "files:trash"),
            MenuItem(name: "Now Playing", icon: "sf:play.circle.fill", provider: "media:now",
                     description: "Music and Spotify: what's playing, play/pause, next, previous."),
        ], description: "Recent files, downloads, drives, the Trash and what's playing.")
    }

    func children(_ provider: String) -> [MenuItem] {
        switch provider {
        case "files:recent": return fileList("recent")
        case "files:downloads": return fileList("downloads")
        case "files:drives": return drives()
        case "files:trash": return trash()
        default: return []
        }
    }

    // MARK: Spotlight lists

    private func fileList(_ kind: String) -> [MenuItem] {
        if let c = lists[kind], Date().timeIntervalSince(c.time) < 20 {
            var items = c.urls.prefix(25).map(FilesMenu.fileItem)
            if items.isEmpty { items = [MenuItem(id: "files:empty-" + kind, name: "Nothing here", icon: "sf:tray")] }
            if kind == "downloads" {
                items.append(MenuItem(id: "files:open-downloads", name: "Open Downloads", icon: "sf:folder",
                                      action: .open(NSHomeDirectory() + "/Downloads")))
            }
            return items
        }
        load(kind)
        return [MenuItem(id: "files:loading-" + kind, name: "Searching…", icon: "sf:hourglass")]
    }

    static func fileItem(_ url: URL) -> MenuItem {
        let isApp = url.pathExtension == "app"
        let name = isApp ? url.deletingPathExtension().lastPathComponent : FileManager.default.displayName(atPath: url.path)
        let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        return MenuItem(id: "file:" + url.path, name: name, icon: "file:" + url.path, action: .open(url.path), description: "In \(folder)")
    }

    private func load(_ kind: String) {
        guard !loading.contains(kind) else { return }
        loading.insert(kind)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = kind == "recent" ? FilesMenu.recent() : FilesMenu.downloads()
            DispatchQueue.main.async {
                self?.loading.remove(kind)
                self?.lists[kind] = (Date(), urls)
                self?.onUpdate?("files:" + kind)
            }
        }
    }

    private static func mdfind(_ query: String, in folder: String) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["-onlyin", folder, query]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    private static func date(_ path: String, _ key: CFString) -> Date {
        guard let item = MDItemCreate(nil, path as CFString) else { return .distantPast }
        return (MDItemCopyAttribute(item, key) as? Date) ?? .distantPast
    }

    /// Documents opened this week, newest first (not apps, Library or hidden files).
    static func recent() -> [URL] {
        let home = NSHomeDirectory()
        let paths = mdfind("kMDItemLastUsedDate >= $time.today(-7) && kMDItemContentTypeTree != \"com.apple.application-bundle\" && kMDItemContentType != \"public.folder\"", in: home)
            .filter { !$0.contains("/Library/") && !$0.contains("/.") && !$0.contains(".app/") }
        return paths.map { ($0, date($0, kMDItemLastUsedDate)) }.sorted { $0.1 > $1.1 }.prefix(25).map { URL(fileURLWithPath: $0.0) }
    }

    /// The Downloads folder's own items (not their contents), newest first.
    static func downloads() -> [URL] {
        let folder = NSHomeDirectory() + "/Downloads"
        let paths = mdfind("kMDItemDateAdded >= $time.today(-365)", in: folder)
            .filter { ($0 as NSString).deletingLastPathComponent == folder && !($0 as NSString).lastPathComponent.hasPrefix(".") }
        return paths.map { ($0, date($0, kMDItemDateAdded)) }.sorted { $0.1 > $1.1 }.prefix(25).map { URL(fileURLWithPath: $0.0) }
    }

    // MARK: Drives

    private func drives() -> [MenuItem] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
                                      .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        let fmt = ByteCountFormatter()
        return volumes.compactMap { v in
            guard let r = try? v.resourceValues(forKeys: Set(keys)) else { return nil }
            let name = r.volumeName ?? v.lastPathComponent
            let free = r.volumeAvailableCapacityForImportantUsage.map { fmt.string(fromByteCount: $0) } ?? "?"
            let total = r.volumeTotalCapacity.map { fmt.string(fromByteCount: Int64($0)) } ?? "?"
            let ejectable = (r.volumeIsEjectable ?? false) || (r.volumeIsRemovable ?? false) || r.volumeIsInternal == false
            var kids = [MenuItem(id: "drive-open:" + v.path, name: "Open", icon: "sf:folder", action: .open(v.path))]
            if ejectable && v.path != "/" {
                kids.append(MenuItem(id: "drive-eject:" + v.path, name: "Eject", icon: "sf:eject.fill",
                                     action: .builtin("files:eject:" + (v.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? v.path))))
            }
            return MenuItem(id: "drive:" + v.path, name: "\(name) · \(free) free", icon: ejectable ? "sf:externaldrive.fill" : "sf:internaldrive.fill",
                            children: kids, description: "\(free) free of \(total).")
        }
    }

    // MARK: Trash

    private func trash() -> [MenuItem] {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let count = (try? FileManager.default.contentsOfDirectory(atPath: trash.path).filter { !$0.hasPrefix(".") }.count)
        return [
            MenuItem(id: "trash:open", name: count.map { "Open Trash (\($0) items)" } ?? "Open Trash", icon: "sf:trash", action: .builtin("files:trash-open")),
            MenuItem(id: "trash:empty", name: "Empty Trash…", icon: "sf:trash.slash.fill", action: .builtin("files:trash-empty"),
                     description: "Asks first. Emptied files can't be recovered."),
        ]
    }

    // MARK: Actions

    /// "files:eject:<path>", "files:trash-open", "files:trash-empty", "files:quicklook:<path>",
    /// "files:compress:<path>", "files:trash-item:<path>". Returns a message to show, if any.
    func perform(_ builtin: String, theme: Theme) -> String? {
        let parts = builtin.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        let path = parts.count > 2 ? (parts[2].removingPercentEncoding ?? parts[2]) : ""
        let url = URL(fileURLWithPath: path)
        switch parts[1] {
        case "eject":
            do { try NSWorkspace.shared.unmountAndEjectDevice(at: url); return "Ejected \(url.lastPathComponent)." }
            catch { return "Couldn't eject \(url.lastPathComponent): \(error.localizedDescription)" }
        case "trash-open":
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
        case "trash-empty":
            let alert = NSAlert()
            alert.messageText = "Empty the Trash?"
            alert.informativeText = "Everything in the Trash will be deleted permanently. This can't be undone."
            alert.addButton(withTitle: "Empty Trash")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
            return error == nil ? "Trash emptied." : "Couldn't empty the Trash."
        case "quicklook":
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
            p.arguments = ["-p", path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
        case "compress":
            let zip = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".zip")
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", path, zip.path]
                try? p.run()
                p.waitUntilExit()
                if p.terminationStatus == 0 { DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([zip]) } }
            }
        case "trash-item":
            NSWorkspace.shared.recycle([url]) { _, error in
                if let error { Log.error("files: couldn't trash \(url.lastPathComponent): \(error.localizedDescription)") }
            }
            lists = [:]
            return "Moved \(url.lastPathComponent) to the Trash."
        default: break
        }
        return nil
    }
}
