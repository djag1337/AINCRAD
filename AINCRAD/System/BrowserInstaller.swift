import AppKit

/// Opt-in install of AINCRAD Browser from its GitHub release. Nothing is downloaded until the user
/// approves a prompt that names the address, the size and where it goes; removing it moves it to the Trash.
enum BrowserInstaller {
    static let releasePage = "https://github.com/djag1337/AINCRAD-Browser"
    /// The zip attached to the latest release. `defaults write com.djag.aincrad browserInstallURL <url>` overrides it (for testing).
    static var downloadURL: URL {
        if let override = UserDefaults.standard.string(forKey: "browserInstallURL"), let url = URL(string: override) { return url }
        return URL(string: releasePage + "/releases/latest/download/AINCRAD-Browser.zip")!
    }

    struct Failure: LocalizedError { let errorDescription: String? }

    /// Asks first, then downloads, checks, installs and opens it. `done` gets nil on success or a message.
    @MainActor
    static func installWithApproval(progress: @escaping (String) -> Void, done: @escaping (String?) -> Void) {
        let url = downloadURL
        let alert = NSAlert()
        alert.messageText = "Download and install AINCRAD Browser?"
        alert.informativeText = """
        AINCRAD will download a zip from:
        \(url.absoluteString)

        and put “AINCRAD Browser” in your Applications folder. It's a separate app that follows your AINCRAD theme and lists its tabs in the launcher. Linking the two needs no macOS permissions. You can remove it here any time (it goes to the Trash).
        """
        alert.addButton(withTitle: "Download and Install")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { done("Cancelled. Nothing was downloaded."); return }
        progress("Downloading…")
        URLSession.shared.downloadTask(with: url) { tmp, response, error in
            let result: Result<URL, Error>
            if let error { result = .failure(error) }
            else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failure(Failure(errorDescription: "GitHub answered \(http.statusCode) for that address. The release may not be published yet, or the repository is private."))
            } else if let tmp { result = place(zip: tmp) }
            else { result = .failure(Failure(errorDescription: "The download didn't arrive.")) }
            DispatchQueue.main.async {
                switch result {
                case .success(let app):
                    NSWorkspace.shared.openApplication(at: app, configuration: .init())
                    done(nil)
                case .failure(let error): done("Couldn't install AINCRAD Browser: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    /// Unzips into a scratch folder, checks it really is AINCRAD Browser and validly signed, then moves it into place.
    private static func place(zip: URL) -> Result<URL, Error> {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("aincrad-browser-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        do {
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            guard run("/usr/bin/ditto", ["-x", "-k", zip.path, scratch.path]) == 0 else { throw Failure(errorDescription: "That file isn't a valid zip.") }
            guard let app = try fm.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
                throw Failure(errorDescription: "The zip had no app inside.")
            }
            guard Bundle(url: app)?.bundleIdentifier == BrowserLink.bundleID else { throw Failure(errorDescription: "The app inside isn't AINCRAD Browser, so it wasn't installed.") }
            guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else { throw Failure(errorDescription: "The app's signature didn't verify, so it wasn't installed.") }
            for folder in ["/Applications", NSHomeDirectory() + "/Applications"] {
                try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
                let dest = URL(fileURLWithPath: folder).appendingPathComponent("AINCRAD Browser.app")
                if fm.fileExists(atPath: dest.path) { throw Failure(errorDescription: "AINCRAD Browser is already in \(folder).") }
                do { try fm.moveItem(at: app, to: dest); registerWithLaunchServices(dest); return .success(dest) }
                catch { continue }
            }
            throw Failure(errorDescription: "Couldn't write to /Applications or ~/Applications.")
        } catch { return .failure(error) }
    }

    private static func registerWithLaunchServices(_ app: URL) {
        _ = run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister", ["-f", app.path])
    }

    private static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    /// Moves the app to the Trash (never deletes it), after asking.
    @MainActor
    static func removeWithApproval(done: @escaping (String?) -> Void) {
        guard let app = BrowserLink.appURL else { done("AINCRAD Browser isn't installed."); return }
        let alert = NSAlert()
        alert.messageText = "Remove AINCRAD Browser?"
        alert.informativeText = "It moves to the Trash. Your bookmarks and history stay in case you reinstall. AINCRAD's launcher menu for it disappears."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { done(nil); return }
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: BrowserLink.bundleID) { running.terminate() }
        NSWorkspace.shared.recycle([app]) { _, error in
            DispatchQueue.main.async { done(error.map { "Couldn't move it to the Trash: \($0.localizedDescription)" }) }
        }
    }
}
