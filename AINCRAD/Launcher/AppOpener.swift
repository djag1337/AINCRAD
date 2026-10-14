import AppKit

/// Opens an app the way a Dock click does: launch it, or for a running app unhide it and send it
/// a "reopen" (which most apps answer by restoring a minimized window or opening a new one).
/// If every window is still minimized afterwards, it un-minimizes the latest one through
/// Accessibility, since some apps ignore reopen.
enum AppOpener {
    static func open(_ url: URL, bundleID: String? = nil, failed: ((String) -> Void)? = nil) {
        let id = bundleID ?? Bundle(url: url)?.bundleIdentifier
        let running = id.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        running?.unhide()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            DispatchQueue.main.async {
                if let error {
                    Log.error("open \(url.lastPathComponent): \(error.localizedDescription)")
                    failed?(error.localizedDescription)
                    return
                }
                guard running != nil, let app = app ?? running else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { restoreMinimized(app) }
            }
        }
        Log.info("open app \(url.lastPathComponent)\(running != nil ? " (running)" : "")")
    }

    private static func restoreMinimized(_ app: NSRunningApplication) {
        guard AXIsProcessTrusted() else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement], !windows.isEmpty else { return }
        func minimized(_ w: AXUIElement) -> Bool {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &v) == .success && (v as? Bool) == true
        }
        // Windows come front-to-back; act only when nothing is showing.
        guard windows.allSatisfy(minimized), let w = windows.first else { return }
        AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        app.activate(options: [])
        Log.info("open app: restored a minimized \(app.localizedName ?? "?") window")
    }
}
