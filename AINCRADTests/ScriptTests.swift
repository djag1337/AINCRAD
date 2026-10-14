import XCTest
@testable import AINCRAD

final class FakeHost: ScriptHost {
    var calls: [String] = []
    var running: Set<String> = []
    func openApp(_ n: String) -> Bool { calls.append("app:\(n)"); return true }
    func openURL(_ u: String) -> Bool { calls.append("url:\(u)"); return true }
    func openFile(_ p: String) -> Bool { calls.append("file:\(p)"); return true }
    func runShortcut(_ n: String) { calls.append("shortcut:\(n)") }
    func openLauncher() { calls.append("launcher") }
    func showMessage(_ t: String, from: String) { calls.append("msg:\(t)") }
    func setGauge(_ k: String, title: String, text: String, fraction: Double?) {
        calls.append("gauge:\(k)=\(text)@\(fraction.map { String(format: "%.2f", $0) } ?? "-")")
    }
    func switchTheme(_ id: String) -> Bool { calls.append("theme:\(id)"); return true }
    func setWidgetsVisible(_ on: Bool) { calls.append("widgets:\(on)") }
    func isAppRunning(_ n: String) -> Bool { running.contains(n) }
}

final class ScriptTests: XCTestCase {
    func make(_ op: String, _ inputs: [String: Block] = [:], fields: [String: String] = [:], body: [Block]? = nil, elseBody: [Block]? = nil) -> Block {
        var b = BlockSpec.spec(op)!.make()
        inputs.forEach { b.inputs[$0.key] = $0.value }
        fields.forEach { b.fields[$0.key] = $0.value }
        if let body { b.body = body }
        if let elseBody { b.elseBody = elseBody }
        return b
    }
    func lit(_ s: String) -> Block { .literal(s) }

    func run(_ steps: [Block], perms: Set<String> = [], host: FakeHost = FakeHost(), log: ((String) -> Void)? = nil) -> (FakeHost, ScriptEngine) {
        let engine = ScriptEngine(context: .init(extensionID: "t", extensionName: "Test", folder: nil, permissions: perms), host: host)
        var lines: [String] = []
        engine.log = { lines.append($0); log?($0) }
        engine.run(Script(trigger: make("ext.started"), steps: steps))
        return (host, engine)
    }

    func testEveryBlockSpecParsesAndMakesFilledBlocks() {
        for spec in BlockSpec.all {
            let b = spec.make()
            let parts = BlockSpec.parse(spec.label)
            for case .input(let name) in parts { XCTAssertNotNil(b.inputs[name], "\(spec.op).\(name)") }
            for case .field(let name) in parts { XCTAssertNotNil(b.fields[name], "\(spec.op).\(name)") }
        }
        XCTAssertEqual(BlockSpec.parse("set [name] to {value}"), [.text("set"), .field("name"), .text("to"), .input("value")])
    }

    func testVariablesMathAndJoin() {
        let (_, e) = run([
            make("var.set", ["value": lit("5")], fields: ["name": "x"]),
            make("var.change", ["value": lit("2")], fields: ["name": "x"]),
            make("var.set", ["value": make("op.join", ["a": lit("x is "), "b": make("var.get", fields: ["name": "x"])])], fields: ["name": "msg"]),
            make("var.set", ["value": make("op.div", ["a": lit("7"), "b": lit("0")])], fields: ["name": "safe"]),
        ])
        XCTAssertEqual(e.variables["x"], .number(7))
        XCTAssertEqual(e.variables["msg"]?.description, "x is 7")
        XCTAssertEqual(e.variables["safe"], .number(0), "divide by zero is 0, not a crash")
    }

    func testIfElseRepeatAndActions() {
        let host = FakeHost()
        host.running = ["Steam"]
        _ = run([
            make("control.ifElse", ["condition": make("sense.appRunning", ["app": lit("Steam")])],
                 body: [make("looks.theme", ["theme": lit("gungale")])],
                 elseBody: [make("looks.theme", ["theme": lit("classic")])]),
            make("control.repeat", ["times": lit("3")], body: [make("act.openURL", ["url": lit("https://a.example")])]),
            make("looks.gauge", ["name": lit("hp"), "text": lit("75 HP"), "percent": lit("75")]),
            make("looks.gauge", ["name": lit("note"), "text": lit("text only"), "percent": lit("")]),
            make("looks.widgets", fields: ["mode": "hide"]),
        ], host: host)
        XCTAssertEqual(host.calls, ["theme:gungale", "url:https://a.example", "url:https://a.example", "url:https://a.example",
                                    "gauge:script:t/hp=75 HP@0.75", "gauge:script:t/note=text only@-", "widgets:false"])
    }

    func testStopEndsTheScript() {
        let (host, _) = run([make("act.openLauncher"), make("control.stop"), make("act.openLauncher")])
        XCTAssertEqual(host.calls, ["launcher"])
    }

    func testEndlessLoopHitsStepLimit() {
        var lines: [String] = []
        let inner = make("control.repeat", ["times": lit("1000")], body: [make("var.change", ["value": lit("1")], fields: ["name": "n"])])
        let (_, e) = run([make("control.repeat", ["times": lit("1000")], body: [inner])], log: { lines.append($0) })
        XCTAssertLessThan(e.variables["n"]!.number, 1_000_000)
        XCTAssertTrue(lines.contains { $0.contains("steps") }, "\(lines)")
    }

    func testNetworkBlockNeedsPermission() {
        var lines: [String] = []
        _ = run([make("var.set", ["value": make("sense.fetch", ["url": lit("https://example.com")])], fields: ["name": "x"])],
                log: { lines.append($0) })
        XCTAssertTrue(lines.contains { $0.contains("network permission") }, "\(lines)")
        let s = [Script(trigger: make("ext.started"), steps: [make("var.log", ["text": make("sense.fetch")])])]
        XCTAssertEqual(ScriptEngine.requiredPermissions(s), ["network"])
    }

    func testJSONAndComparisons() {
        let (_, e) = run([
            make("var.set", ["value": make("sense.json", ["path": lit("a.b.1"), "json": lit(#"{"a":{"b":[1, 42]}}"#)])], fields: ["name": "v"]),
            make("var.set", ["value": make("op.gt", ["a": make("var.get", fields: ["name": "v"]), "b": lit("9")])], fields: ["name": "big"]),
            make("var.set", ["value": make("op.eq", ["a": lit("Kirito"), "b": lit("kirito")])], fields: ["name": "same"]),
        ])
        XCTAssertEqual(e.variables["v"], .number(42))
        XCTAssertEqual(e.variables["big"], .bool(true), "42 > 9 numerically, not as text")
        XCTAssertEqual(e.variables["same"], .bool(true))
    }

    func testReadingsAreSane() {
        let (_, e) = run([make("var.set", ["value": make("sense.reading", fields: ["reading": "memory"])], fields: ["name": "m"])])
        XCTAssertTrue((1...100).contains(e.variables["m"]!.number))
    }

    func testScriptsRoundTripAndManifestValidation() throws {
        let script = Script(trigger: make("timer.every"), steps: [make("var.log", ["text": make("sense.fetch")])])
        let decoded = try JSONDecoder().decode(Script.self, from: TolerantJSON.encode(script))
        XCTAssertEqual(decoded, script)
        var m = ExtensionManifest(id: "a.b", name: "A", version: "1", apiVersion: 1, permissions: [], provides: .init(scripts: [script]))
        XCTAssertNotNil(ExtensionManager.validate(m), "fetch block without the network permission")
        m.permissions = ["network"]
        XCTAssertNil(ExtensionManager.validate(m))
        m.provides.scripts![0].steps.append(Block(op: "evil.deleteEverything"))
        XCTAssertNotNil(ExtensionManager.validate(m), "unknown blocks are refused")
    }
}

final class ScriptDecodingTests: XCTestCase {
    func testHandWrittenScriptNeedsOnlyTrigger() throws {
        let s = try JSONDecoder().decode(Script.self, from: Data(#"{"trigger": {"op": "ext.started"}}"#.utf8))
        XCTAssertFalse(s.id.isEmpty)
        XCTAssertTrue(s.steps.isEmpty)
    }
}
