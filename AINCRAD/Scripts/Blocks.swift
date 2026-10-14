import Foundation

/// One Scratch-style block. Statements run in order; reporters sit in another block's inputs and
/// produce a value. Literal values are reporter blocks with op "literal".
struct Block: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var op: String
    /// Fixed choices and names (dropdowns, variable names).
    var fields: [String: String] = [:]
    /// Value slots, each holding a reporter (often a literal).
    var inputs: [String: Block] = [:]
    /// Inner stack of C-blocks (if, repeat).
    var body: [Block]? = nil
    var elseBody: [Block]? = nil

    static func literal(_ value: String) -> Block { Block(op: "literal", fields: ["value": value]) }

    var literalValue: String? { op == "literal" ? fields["value"] ?? "" : nil }

    /// Deep copy with fresh ids, for blocks dragged out of the palette or duplicated.
    func renewed() -> Block {
        var b = self
        b.id = UUID().uuidString
        b.inputs = inputs.mapValues { $0.renewed() }
        b.body = body?.map { $0.renewed() }
        b.elseBody = elseBody?.map { $0.renewed() }
        return b
    }

    /// This block and everything nested in it.
    var all: [Block] {
        [self] + inputs.values.flatMap(\.all) + (body ?? []).flatMap(\.all) + (elseBody ?? []).flatMap(\.all)
    }
}

extension Block {
    private enum CodingKeys: String, CodingKey { case id, op, fields, inputs, body, elseBody }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        op = try c.decode(String.self, forKey: .op)
        fields = try c.decodeIfPresent([String: String].self, forKey: .fields) ?? [:]
        inputs = try c.decodeIfPresent([String: Block].self, forKey: .inputs) ?? [:]
        body = try c.decodeIfPresent([Block].self, forKey: .body)
        elseBody = try c.decodeIfPresent([Block].self, forKey: .elseBody)
    }
}

/// An event ("hat") block and the stack it runs.
struct Script: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var trigger: Block
    var steps: [Block] = []

    var allBlocks: [Block] { trigger.all + steps.flatMap(\.all) }
}

extension Script {
    private enum CodingKeys: String, CodingKey { case id, trigger, steps }

    // Hand-written scripts may leave out the id and an empty steps list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        trigger = try c.decode(Block.self, forKey: .trigger)
        steps = try c.decodeIfPresent([Block].self, forKey: .steps) ?? []
    }
}

// MARK: Block catalogue

enum BlockCategory: String, CaseIterable {
    case events, control, actions, looks, sensing, operators, variables

    var title: String {
        switch self {
        case .events: return "Events"
        case .control: return "Control"
        case .actions: return "Actions"
        case .looks: return "Looks"
        case .sensing: return "Sensing"
        case .operators: return "Operators"
        case .variables: return "Variables"
        }
    }

    /// Scratch's palette, so the blocks feel familiar.
    var hex: String {
        switch self {
        case .events: return "#FFBF00"
        case .control: return "#FFAB19"
        case .actions: return "#4C97FF"
        case .looks: return "#9966FF"
        case .sensing: return "#5CB1D6"
        case .operators: return "#59C059"
        case .variables: return "#FF8C1A"
        }
    }
}

struct BlockSpec {
    enum Kind { case hat, statement, cBlock, ifElse, cap, reporter, boolean }

    let op: String
    let kind: Kind
    let category: BlockCategory
    /// "open app {app}" — {name} is a value slot, [name] a dropdown from `options`.
    let label: String
    var defaults: [String: String] = [:]
    var options: [String: [String]] = [:]
    /// Permission a script using this block must declare ("network" / "files").
    var permission: String? = nil
    var help = ""

    var isReporter: Bool { kind == .reporter || kind == .boolean }

    /// A fresh block ready to drop: every slot filled with its default literal.
    func make() -> Block {
        var b = Block(op: op)
        for part in BlockSpec.parse(label) {
            switch part {
            case .input(let name): b.inputs[name] = .literal(defaults[name] ?? "")
            case .field(let name): b.fields[name] = defaults[name] ?? options[name]?.first ?? ""
            case .text: break
            }
        }
        if kind == .cBlock || kind == .ifElse { b.body = [] }
        if kind == .ifElse { b.elseBody = [] }
        return b
    }

    enum Part: Equatable { case text(String), input(String), field(String) }

    static func parse(_ label: String) -> [Part] {
        var parts: [Part] = [], buffer = ""
        var i = label.startIndex
        while i < label.endIndex {
            let ch = label[i]
            if ch == "{" || ch == "[", let close = label[i...].firstIndex(of: ch == "{" ? "}" : "]") {
                if !buffer.isEmpty { parts.append(.text(buffer.trimmingCharacters(in: .whitespaces))); buffer = "" }
                let name = String(label[label.index(after: i)..<close])
                parts.append(ch == "{" ? .input(name) : .field(name))
                i = label.index(after: close)
            } else {
                buffer.append(ch)
                i = label.index(after: i)
            }
        }
        if !buffer.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(.text(buffer.trimmingCharacters(in: .whitespaces))) }
        return parts.filter { $0 != .text("") }
    }

    static let readings = ["CPU", "memory", "disk", "battery", "uptime hours"]

    static let all: [BlockSpec] = [
        // Events
        BlockSpec(op: "ext.started", kind: .hat, category: .events, label: "when extension starts",
                  help: "Runs once when the extension is enabled or AINCRAD starts."),
        BlockSpec(op: "launcher.opened", kind: .hat, category: .events, label: "when the launcher opens"),
        BlockSpec(op: "item.chosen", kind: .hat, category: .events, label: "when menu item {name} is chosen",
                  defaults: ["name": "Safari"], help: "Leave the name empty to react to any item."),
        BlockSpec(op: "timer.every", kind: .hat, category: .events, label: "every {seconds} seconds",
                  defaults: ["seconds": "60"], help: "At least 2 seconds."),
        BlockSpec(op: "app.launched", kind: .hat, category: .events, label: "when app {app} opens",
                  defaults: ["app": "Steam"], help: "App name or bundle id."),
        BlockSpec(op: "app.quit", kind: .hat, category: .events, label: "when app {app} quits", defaults: ["app": "Steam"]),
        // Control
        BlockSpec(op: "control.wait", kind: .statement, category: .control, label: "wait {seconds} seconds",
                  defaults: ["seconds": "1"], help: "Up to 30 seconds."),
        BlockSpec(op: "control.if", kind: .cBlock, category: .control, label: "if {condition} then"),
        BlockSpec(op: "control.ifElse", kind: .ifElse, category: .control, label: "if {condition} then"),
        BlockSpec(op: "control.repeat", kind: .cBlock, category: .control, label: "repeat {times} times",
                  defaults: ["times": "3"], help: "Up to 1000 times."),
        BlockSpec(op: "control.stop", kind: .cap, category: .control, label: "stop this script"),
        // Actions
        BlockSpec(op: "act.openApp", kind: .statement, category: .actions, label: "open app {app}", defaults: ["app": "Safari"]),
        BlockSpec(op: "act.openURL", kind: .statement, category: .actions, label: "open website {url}",
                  defaults: ["url": "https://www.apple.com"]),
        BlockSpec(op: "act.openFile", kind: .statement, category: .actions, label: "open file or folder {path}",
                  defaults: ["path": "~/Documents"]),
        BlockSpec(op: "act.shortcut", kind: .statement, category: .actions, label: "run Shortcut {name}",
                  defaults: ["name": "My Shortcut"]),
        BlockSpec(op: "act.openLauncher", kind: .statement, category: .actions, label: "open the launcher"),
        // Looks
        BlockSpec(op: "looks.message", kind: .statement, category: .looks, label: "show message {text}",
                  defaults: ["text": "Welcome to Sword Art Online!"], help: "An SAO-style message near the top of the screen."),
        BlockSpec(op: "looks.gauge", kind: .statement, category: .looks, label: "set gauge {name} to {text} level {percent} %",
                  defaults: ["name": "gauge", "text": "Hello", "percent": "50"],
                  help: "Shows on any stat widget whose source is this gauge. Leave level empty for text only."),
        BlockSpec(op: "looks.theme", kind: .statement, category: .looks, label: "switch theme to {theme}",
                  defaults: ["theme": "aincrad-dark"]),
        BlockSpec(op: "looks.widgets", kind: .statement, category: .looks, label: "[mode] desktop widgets",
                  options: ["mode": ["show", "hide"]]),
        // Sensing
        BlockSpec(op: "sense.reading", kind: .reporter, category: .sensing, label: "[reading] %",
                  options: ["reading": readings], help: "CPU, memory and disk are percent used; battery is percent charged."),
        BlockSpec(op: "sense.time", kind: .reporter, category: .sensing, label: "current [part]",
                  options: ["part": ["hour", "minute", "second", "weekday", "date", "time"]]),
        BlockSpec(op: "sense.appRunning", kind: .boolean, category: .sensing, label: "app {app} is running",
                  defaults: ["app": "Steam"]),
        BlockSpec(op: "sense.fetch", kind: .reporter, category: .sensing, label: "fetch {url}",
                  defaults: ["url": "https://api.example.com/data.json"], permission: "network",
                  help: "Downloads text from the web (needs the network permission)."),
        BlockSpec(op: "sense.readFile", kind: .reporter, category: .sensing, label: "read file {path}",
                  defaults: ["path": "data.json"], help: "Inside the extension folder; anywhere else needs the files permission."),
        BlockSpec(op: "sense.json", kind: .reporter, category: .sensing, label: "item {path} of JSON {json}",
                  defaults: ["path": "current.temperature"]),
        // Operators
        BlockSpec(op: "op.add", kind: .reporter, category: .operators, label: "{a} + {b}"),
        BlockSpec(op: "op.sub", kind: .reporter, category: .operators, label: "{a} − {b}"),
        BlockSpec(op: "op.mul", kind: .reporter, category: .operators, label: "{a} × {b}"),
        BlockSpec(op: "op.div", kind: .reporter, category: .operators, label: "{a} ÷ {b}"),
        BlockSpec(op: "op.round", kind: .reporter, category: .operators, label: "round {a}"),
        BlockSpec(op: "op.random", kind: .reporter, category: .operators, label: "pick random {a} to {b}",
                  defaults: ["a": "1", "b": "10"]),
        BlockSpec(op: "op.join", kind: .reporter, category: .operators, label: "join {a} {b}",
                  defaults: ["a": "hello ", "b": "world"]),
        BlockSpec(op: "op.lt", kind: .boolean, category: .operators, label: "{a} < {b}"),
        BlockSpec(op: "op.gt", kind: .boolean, category: .operators, label: "{a} > {b}"),
        BlockSpec(op: "op.eq", kind: .boolean, category: .operators, label: "{a} = {b}"),
        BlockSpec(op: "op.and", kind: .boolean, category: .operators, label: "{a} and {b}"),
        BlockSpec(op: "op.or", kind: .boolean, category: .operators, label: "{a} or {b}"),
        BlockSpec(op: "op.not", kind: .boolean, category: .operators, label: "not {a}"),
        // Variables
        BlockSpec(op: "var.set", kind: .statement, category: .variables, label: "set [name] to {value}",
                  defaults: ["name": "score", "value": "0"]),
        BlockSpec(op: "var.change", kind: .statement, category: .variables, label: "change [name] by {value}",
                  defaults: ["name": "score", "value": "1"]),
        BlockSpec(op: "var.get", kind: .reporter, category: .variables, label: "[name]", defaults: ["name": "score"]),
        BlockSpec(op: "var.log", kind: .statement, category: .variables, label: "log {text}", defaults: ["text": "hello"],
                  help: "Writes to the Studio's test console and AINCRAD's log."),
    ]

    private static let byOp = Dictionary(uniqueKeysWithValues: all.map { ($0.op, $0) })
    static func spec(_ op: String) -> BlockSpec? { byOp[op] }

    /// Variable names are free text in `var.*` blocks, so their dropdown offers names already used.
    static var variableOps: Set<String> { ["var.set", "var.change", "var.get"] }
}
