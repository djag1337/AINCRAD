import AppKit

/// Connects enabled extensions' scripts to events. Each script runs on a background queue, one
/// run at a time (a trigger that fires while it's still running is skipped). Timers exist only
/// for "every N seconds" scripts of enabled extensions.
final class ScriptRuntime {
    struct Loaded {
        let ext: LoadedExtension
        let scripts: [Script]
    }

    weak var host: ScriptHost?
    /// Receives every log line, tagged with the extension id (the Studio shows these live).
    var onLog: ((String, String) -> Void)?

    private var loaded: [Loaded] = []
    private var engines: [String: ScriptEngine] = [:]   // per extension, so variables persist between runs
    /// One serial queue per extension: its scripts share an engine, so they take turns.
    private var queues: [String: DispatchQueue] = [:]
    private var running = Set<String>()
    private var timers: [DispatchSourceTimer] = []
    private var observers: [NSObjectProtocol] = []
    private let queue = DispatchQueue(label: "aincrad.scripts", qos: .utility, attributes: .concurrent)
    private let lock = NSLock()

    func load(_ extensions: [LoadedExtension]) {
        stop()
        loaded = extensions.compactMap { ext in
            let s = ext.manifest.provides.scripts ?? []
            return s.isEmpty ? nil : Loaded(ext: ext, scripts: s)
        }
        guard !loaded.isEmpty else { return }
        for l in loaded {
            engines[l.ext.id] = makeEngine(for: l.ext)
            queues[l.ext.id] = DispatchQueue(label: "aincrad.scripts.\(l.ext.id)", qos: .utility)
            for script in l.scripts where script.trigger.op == "timer.every" {
                let seconds = max(2, Double(triggerValue(script, "seconds", l.ext)) ?? 60)
                let t = DispatchSource.makeTimerSource(queue: queue)
                t.schedule(deadline: .now() + seconds, repeating: seconds, leeway: .milliseconds(Int(seconds * 100)))
                t.setEventHandler { [weak self] in self?.start(script, in: l.ext.id) }
                t.resume()
                timers.append(t)
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for (name, op) in [(NSWorkspace.didLaunchApplicationNotification, "app.launched"),
                           (NSWorkspace.didTerminateApplicationNotification, "app.quit")] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.fire(op) { ext, script in ScriptRuntime.matches(app, self?.triggerValue(script, "app", ext) ?? "") }
            })
        }
        fire("ext.started")
        Log.info("scripts: \(loaded.map(\.scripts.count).reduce(0, +)) loaded from \(loaded.count) extensions, \(timers.count) timers")
    }

    func stop() {
        timers.forEach { $0.cancel() }
        timers = []
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        loaded = []
        engines = [:]
        queues = [:]
    }

    func launcherOpened() { fire("launcher.opened") }

    func itemChosen(_ name: String) {
        fire("item.chosen") { [weak self] ext, script in
            let want = self?.triggerValue(script, "name", ext) ?? ""
            return want.isEmpty || want.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Runs one script immediately (the Studio's ▶ button), with an engine for that extension.
    func test(_ script: Script, ext: LoadedExtension, log: @escaping (String) -> Void) {
        let engine = makeEngine(for: ext)
        engine.log = log
        queue.async {
            let t0 = Date()
            engine.run(script)
            log(String(format: "finished in %.2f s · variables: %@", Date().timeIntervalSince(t0),
                       engine.variables.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")))
        }
    }

    static func matches(_ app: NSRunningApplication, _ want: String) -> Bool {
        let w = want.trimmingCharacters(in: .whitespaces)
        return !w.isEmpty && (app.bundleIdentifier?.caseInsensitiveCompare(w) == .orderedSame
            || app.localizedName?.caseInsensitiveCompare(w) == .orderedSame)
    }

    // MARK: Private

    private func makeEngine(for ext: LoadedExtension) -> ScriptEngine {
        let ctx = ScriptEngine.Context(extensionID: ext.id, extensionName: ext.manifest.name, folder: ext.folder,
                                       permissions: ext.requested)
        let engine = ScriptEngine(context: ctx, host: host)
        engine.log = { [weak self] line in
            Log.info("script[\(ext.id)] \(line)")
            DispatchQueue.main.async { self?.onLog?(ext.id, line) }
        }
        return engine
    }

    /// An event block's setting, evaluated on a throwaway engine so it never touches a running one.
    private func triggerValue(_ script: Script, _ name: String, _ ext: LoadedExtension) -> String {
        if let v = script.trigger.inputs[name]?.literalValue { return v }
        let ctx = ScriptEngine.Context(extensionID: ext.id, extensionName: ext.manifest.name, folder: ext.folder, permissions: [])
        return (try? ScriptEngine(context: ctx, host: nil).eval(script.trigger.inputs[name]).description) ?? ""
    }

    private func fire(_ op: String, where match: ((LoadedExtension, Script) -> Bool)? = nil) {
        for l in loaded {
            for script in l.scripts where script.trigger.op == op {
                if let match, !match(l.ext, script) { continue }
                start(script, in: l.ext.id)
            }
        }
    }

    private func start(_ script: Script, in extID: String) {
        lock.lock()
        guard let engine = engines[extID], let q = queues[extID], !running.contains(script.id) else { lock.unlock(); return }
        running.insert(script.id)
        lock.unlock()
        q.async { [weak self] in
            engine.run(script)
            self?.lock.lock()
            self?.running.remove(script.id)
            self?.lock.unlock()
        }
    }
}
