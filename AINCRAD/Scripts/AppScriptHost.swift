import AppKit

/// The app side of `ScriptHost`: what blocks are allowed to do, implemented with the same
/// pieces the launcher uses.
final class AppScriptHost: ScriptHost {
    private let store: ConfigStore
    private let message = MessagePanel()
    var openLauncherAction: () -> Void = {}
    var reloadAction: () -> Void = {}
    var widgetsChanged: () -> Void = {}

    init(store: ConfigStore) { self.store = store }

    /// App name ("Safari"), bundle id ("com.apple.Safari") or path.
    static func appURL(_ nameOrID: String) -> URL? {
        if let url = ActionRunner.appURL(nameOrID) { return url }
        let name = nameOrID.hasSuffix(".app") ? String(nameOrID.dropLast(4)) : nameOrID
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"] {
            let path = "\(dir)/\(name).app"
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    func openApp(_ nameOrID: String) -> Bool {
        guard let url = AppScriptHost.appURL(nameOrID) else { return false }
        ActionRunner.run(.app(url.path), builtin: { _ in })
        return true
    }

    func openURL(_ url: String) -> Bool {
        guard let u = URL(string: url), u.scheme != nil else { return false }
        NSWorkspace.shared.open(u)
        return true
    }

    func openFile(_ path: String) -> Bool {
        let p = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: p) else { return false }
        NSWorkspace.shared.open(URL(fileURLWithPath: p))
        return true
    }

    func runShortcut(_ name: String) { ActionRunner.run(.shortcut(name), builtin: { _ in }) }

    func openLauncher() { openLauncherAction() }

    func showMessage(_ text: String, from extensionName: String) {
        let reduced = store.settings.reducedMotion == "on"
            || (store.settings.reducedMotion == "system" && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        message.show(text, title: "Message", theme: store.theme, reducedMotion: reduced)
        Log.info("message from \(extensionName): \(text)")
    }

    func setGauge(_ key: String, title: String, text: String, fraction: Double?) {
        DataHub.shared.push(key, title: title, StatSample(fraction: fraction, text: text))
    }

    func switchTheme(_ id: String) -> Bool {
        guard store.themeIDs().contains(id) else { return false }
        if store.settings.theme != id {
            store.update { $0.theme = id }
            reloadAction()
        }
        return true
    }

    func setWidgetsVisible(_ on: Bool) {
        guard store.settings.widgetsEnabled != on else { return }
        store.update { $0.widgetsEnabled = on }
        widgetsChanged()
    }

    func isAppRunning(_ nameOrID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { ScriptRuntime.matches($0, nameOrID) }
    }
}
