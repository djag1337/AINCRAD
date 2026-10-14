import AppKit

enum ActionRunner {
    /// Set from settings; shell actions are refused unless the user turned this on.
    static var allowShell = false

    static func run(_ action: MenuAction, builtin: (String) -> Void) {
        switch action {
        case .shortcut(let name):
            launch("/usr/bin/shortcuts", ["run", name], label: "shortcut \"\(name)\"")
        case .shell(let command):
            guard allowShell else {
                return fail("shell action blocked: enable \"Allow shell commands\" in Settings › General to run \"\(command)\"")
            }
            launch("/bin/zsh", ["-lc", command], label: "shell \"\(command)\"")
        case .app(let target):
            guard let url = appURL(target) else { return fail("app not found: \(target)") }
            AppOpener.open(url) { fail("launch \(url.lastPathComponent): \($0)") }
        case .open(let path):
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return fail("missing: \(url.path)") }
            NSWorkspace.shared.open(url)
            Log.info("open \(url.path)")
        case .url(let string):
            guard let url = URL(string: string), url.scheme != nil else { return fail("bad url: \(string)") }
            NSWorkspace.shared.open(url)
            Log.info("open url \(string)")
        case .builtin(let name):
            builtin(name)
        }
    }

    static func appURL(_ target: String) -> URL? {
        if target.hasPrefix("/") || target.hasPrefix("~") {
            let path = (target as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: target)
    }

    /// Fire-and-forget; output is discarded, the exit status is logged.
    private static func launch(_ tool: String, _ args: [String], label: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { proc in
            Log.info("\(label) exited with status \(proc.terminationStatus)")
            if proc.terminationStatus != 0 { DispatchQueue.main.async { NSSound.beep() } }
        }
        do {
            try p.run()
            Log.info("run \(label)")
        } catch {
            fail("\(label): \(error.localizedDescription)")
        }
    }

    private static func fail(_ message: String) {
        Log.error(message)
        NSSound.beep()
    }
}
