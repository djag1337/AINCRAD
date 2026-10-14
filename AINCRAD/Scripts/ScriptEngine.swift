import Foundation

/// What scripts can reach in the app. Every call is made on the main thread.
protocol ScriptHost: AnyObject {
    func openApp(_ nameOrID: String) -> Bool
    func openURL(_ url: String) -> Bool
    func openFile(_ path: String) -> Bool
    func runShortcut(_ name: String)
    func openLauncher()
    func showMessage(_ text: String, from extensionName: String)
    func setGauge(_ key: String, title: String, text: String, fraction: Double?)
    func switchTheme(_ id: String) -> Bool
    func setWidgetsVisible(_ on: Bool)
    func isAppRunning(_ nameOrID: String) -> Bool
}

/// Scratch-like values: text that looks like a number acts as a number.
enum ScriptValue: Equatable, CustomStringConvertible {
    case text(String), number(Double), bool(Bool)

    var number: Double {
        switch self {
        case .number(let n): return n
        case .bool(let b): return b ? 1 : 0
        case .text(let s): return Double(s.trimmingCharacters(in: .whitespaces)) ?? 0
        }
    }

    var bool: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .text(let s): return !(s.isEmpty || s == "0" || s.lowercased() == "false")
        }
    }

    var description: String {
        switch self {
        case .text(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .number(let n):
            if n.isFinite, n == n.rounded(), abs(n) < 1e15 { return String(Int64(n)) }
            return String(format: "%.4g", n)
        }
    }

    static func from(_ s: String) -> ScriptValue {
        Double(s.trimmingCharacters(in: .whitespaces)).map { .number($0) } ?? .text(s)
    }
}

enum ScriptError: Error, CustomStringConvertible {
    case stepLimit, timeLimit, permission(String), stopped

    var description: String {
        switch self {
        case .stepLimit: return "stopped: more than \(ScriptEngine.maxSteps) steps (endless loop?)"
        case .timeLimit: return "stopped: ran longer than \(Int(ScriptEngine.maxSeconds)) s"
        case .permission(let p): return "blocked: this extension doesn't have the \(p) permission"
        case .stopped: return "stopped"
        }
    }
}

/// Runs one script run to completion on a background queue, within hard limits: a step budget,
/// a wall-clock budget, capped waits and loops, and permission checks on fetch / file blocks.
final class ScriptEngine {
    static let maxSteps = 20_000
    static let maxSeconds: TimeInterval = 45
    static let maxWait: TimeInterval = 30
    static let maxRepeat = 1000

    struct Context {
        var extensionID: String
        var extensionName: String
        var folder: URL?
        var permissions: Set<String>
        var variables: [String: ScriptValue] = [:]
    }

    weak var host: ScriptHost?
    var log: (String) -> Void = { _ in }
    private let readings = DataHub()
    private var steps = 0
    private var started = Date()
    private var ctx: Context

    init(context: Context, host: ScriptHost?) {
        self.ctx = context
        self.host = host
    }

    var variables: [String: ScriptValue] { ctx.variables }

    /// Permissions a set of scripts needs, derived from the blocks they use.
    static func requiredPermissions(_ scripts: [Script]) -> Set<String> {
        var needed = Set<String>()
        for b in scripts.flatMap(\.allBlocks) {
            if let p = BlockSpec.spec(b.op)?.permission { needed.insert(p) }
            if b.op == "sense.readFile", let path = b.inputs["path"]?.literalValue, path.hasPrefix("/") || path.hasPrefix("~") {
                needed.insert("files")
            }
        }
        return needed
    }

    /// Runs the script's stack. Blocking; call from a background queue.
    func run(_ script: Script) {
        steps = 0
        started = Date()
        do {
            try exec(script.steps)
        } catch ScriptError.stopped {
        } catch {
            log("\(BlockSpec.spec(script.trigger.op)?.label ?? script.trigger.op): \(error)")
        }
    }

    // MARK: Statements

    private func tick() throws {
        steps += 1
        if steps > ScriptEngine.maxSteps { throw ScriptError.stepLimit }
        if Date().timeIntervalSince(started) > ScriptEngine.maxSeconds { throw ScriptError.timeLimit }
    }

    private func exec(_ blocks: [Block]) throws {
        for b in blocks { try exec(b) }
    }

    private func exec(_ b: Block) throws {
        try tick()
        func s(_ k: String) throws -> String { try eval(b.inputs[k]).description }
        func n(_ k: String) throws -> Double { try eval(b.inputs[k]).number }
        switch b.op {
        case "control.wait":
            let t = min(max(try n("seconds"), 0), ScriptEngine.maxWait)
            if Date().timeIntervalSince(started) + t > ScriptEngine.maxSeconds { throw ScriptError.timeLimit }
            Thread.sleep(forTimeInterval: t)
        case "control.if":
            if try eval(b.inputs["condition"]).bool { try exec(b.body ?? []) }
        case "control.ifElse":
            try exec(try eval(b.inputs["condition"]).bool ? (b.body ?? []) : (b.elseBody ?? []))
        case "control.repeat":
            let times = min(max(Int(try n("times")), 0), ScriptEngine.maxRepeat)
            for _ in 0..<times { try exec(b.body ?? []) }
        case "control.stop":
            throw ScriptError.stopped
        case "act.openApp":
            let app = try s("app")
            if !(onMain { $0.openApp(app) } ?? false) { log("open app: couldn't find \"\(app)\"") }
        case "act.openURL":
            let url = try s("url")
            if !(onMain { $0.openURL(url) } ?? false) { log("open website: \"\(url)\" isn't a valid URL") }
        case "act.openFile":
            let path = try s("path")
            if !(onMain { $0.openFile(path) } ?? false) { log("open file: \"\(path)\" doesn't exist") }
        case "act.shortcut":
            let name = try s("name")
            onMain { $0.runShortcut(name) }
        case "act.openLauncher":
            onMain { $0.openLauncher() }
        case "looks.message":
            let text = try s("text"), from = ctx.extensionName
            onMain { $0.showMessage(text, from: from) }
        case "looks.gauge":
            let name = try s("name"), text = try s("text")
            let raw = try eval(b.inputs["percent"]).description.trimmingCharacters(in: .whitespaces)
            let fraction = raw.isEmpty ? nil : min(max(ScriptValue.from(raw).number / 100, 0), 1)
            let key = "script:\(ctx.extensionID)/\(name)"
            onMain { $0.setGauge(key, title: name, text: text, fraction: fraction) }
        case "looks.theme":
            let id = try s("theme")
            if !(onMain { $0.switchTheme(id) } ?? false) { log("switch theme: no theme named \"\(id)\"") }
        case "looks.widgets":
            let on = b.fields["mode"] != "hide"
            onMain { $0.setWidgetsVisible(on) }
        case "var.set":
            ctx.variables[b.fields["name"] ?? ""] = try eval(b.inputs["value"])
        case "var.change":
            let k = b.fields["name"] ?? ""
            ctx.variables[k] = .number((ctx.variables[k]?.number ?? 0) + (try n("value")))
        case "var.log":
            log(try s("text"))
        default:
            // A reporter dropped into a stack: evaluate it for its effects, ignore the value.
            _ = try eval(b)
        }
    }

    // MARK: Reporters

    func eval(_ block: Block?) throws -> ScriptValue {
        guard let b = block else { return .text("") }
        if let v = b.literalValue { return .from(v) }
        try tick()
        func v(_ k: String) throws -> ScriptValue { try eval(b.inputs[k]) }
        switch b.op {
        case "op.add": return .number(try v("a").number + v("b").number)
        case "op.sub": return .number(try v("a").number - v("b").number)
        case "op.mul": return .number(try v("a").number * v("b").number)
        case "op.div":
            let d = try v("b").number
            return .number(d == 0 ? 0 : try v("a").number / d)
        case "op.round": return .number(try v("a").number.rounded())
        case "op.random":
            let a = try v("a").number, c = try v("b").number
            let lo = min(a, c), hi = max(a, c)
            let whole = lo == lo.rounded() && hi == hi.rounded()
            return .number(whole ? Double(Int.random(in: Int(lo)...Int(hi))) : Double.random(in: lo...hi))
        case "op.join": return .text(try v("a").description + v("b").description)
        case "op.lt": return .bool(try compare(v("a"), v("b")) < 0)
        case "op.gt": return .bool(try compare(v("a"), v("b")) > 0)
        case "op.eq": return .bool(try compare(v("a"), v("b")) == 0)
        case "op.and": return .bool(try v("a").bool && v("b").bool)
        case "op.or": return .bool(try v("a").bool || v("b").bool)
        case "op.not": return .bool(!(try v("a").bool))
        case "var.get": return ctx.variables[b.fields["name"] ?? ""] ?? .number(0)
        case "sense.reading": return reading(b.fields["reading"] ?? "CPU")
        case "sense.time": return time(b.fields["part"] ?? "time")
        case "sense.appRunning":
            let app = try v("app").description
            return .bool(onMain { $0.isAppRunning(app) } ?? false)
        case "sense.fetch":
            guard ctx.permissions.contains("network") else { throw ScriptError.permission("network") }
            return .text(fetch(try v("url").description))
        case "sense.readFile":
            return .text(try readFile(try v("path").description))
        case "sense.json":
            return jsonItem(try v("path").description, in: try v("json").description)
        default:
            log("unknown block \(b.op)")
            return .text("")
        }
    }

    private func compare(_ a: ScriptValue, _ b: ScriptValue) -> Int {
        let sa = a.description, sb = b.description
        if let x = Double(sa), let y = Double(sb) { return x < y ? -1 : x > y ? 1 : 0 }
        let r = sa.caseInsensitiveCompare(sb)
        return r == .orderedAscending ? -1 : r == .orderedDescending ? 1 : 0
    }

    private func reading(_ which: String) -> ScriptValue {
        let source: StatSource
        switch which {
        case "memory": source = .memory
        case "disk": source = .disk
        case "battery": source = .battery
        case "uptime hours": return .number(((readings.sample(.uptime)?.used ?? 0) / 3600).rounded())
        default: source = .cpu
        }
        var sample = readings.sample(source)
        if source == .cpu {
            // CPU usage is a difference between two samples.
            Thread.sleep(forTimeInterval: 0.25)
            sample = readings.sample(.cpu)
        }
        return .number(((sample?.fraction ?? 0) * 100).rounded())
    }

    private func time(_ part: String) -> ScriptValue {
        let now = Date(), cal = Calendar.current
        switch part {
        case "hour": return .number(Double(cal.component(.hour, from: now)))
        case "minute": return .number(Double(cal.component(.minute, from: now)))
        case "second": return .number(Double(cal.component(.second, from: now)))
        case "weekday": return .text(now.formatted(.dateTime.weekday(.wide)))
        case "date": return .text(now.formatted(date: .abbreviated, time: .omitted))
        default: return .text(now.formatted(date: .omitted, time: .shortened))
        }
    }

    private func fetch(_ urlString: String) -> String {
        guard let url = URL(string: urlString), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            log("fetch: only http(s) URLs are allowed")
            return ""
        }
        var result = ""
        let done = DispatchSemaphore(value: 0)
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("AINCRAD", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            if let error { self?.log("fetch: \(error.localizedDescription)") }
            result = data.flatMap { String(data: $0.prefix(1_000_000), encoding: .utf8) } ?? ""
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 12)
        return result
    }

    private func readFile(_ path: String) throws -> String {
        let url: URL?
        if path.hasPrefix("/") || path.hasPrefix("~") {
            guard ctx.permissions.contains("files") else { throw ScriptError.permission("files") }
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            url = ctx.folder.flatMap { ExtensionManager.contained(path, in: $0) }
        }
        guard let url, let data = try? Data(contentsOf: url) else {
            log("read file: can't read \"\(path)\"")
            return ""
        }
        return String(data: data.prefix(1_000_000), encoding: .utf8) ?? ""
    }

    private func jsonItem(_ path: String, in json: String) -> ScriptValue {
        let def = ExtensionManifest.DataSourceDef(id: "", name: "", file: "", value: path)
        guard let s = ExtensionManager.sample(from: Data(json.utf8), def: def) else { return .text("") }
        return s.used.map { .number($0) } ?? .text(s.text)
    }

    @discardableResult
    private func onMain<T>(_ body: @escaping (ScriptHost) -> T) -> T? {
        guard let host else { return nil }
        if Thread.isMainThread { return body(host) }
        return DispatchQueue.main.sync { body(host) }
    }
}
