import XCTest
@testable import AINCRAD

final class ScriptTreeTests: XCTestCase {
    func b(_ id: String, _ op: String = "act.openLauncher") -> Block { var x = BlockSpec.spec(op)!.make(); x.id = id; return x }

    func scripts() -> [Script] {
        var loop = b("loop", "control.repeat")
        loop.body = [b("in1"), b("in2")]
        var log = b("log", "var.log")
        log.inputs["text"] = b("join", "op.join")
        return [Script(id: "s1", trigger: b("hat", "ext.started"), steps: [b("a"), loop, log])]
    }

    func ids(_ s: [Script]) -> String {
        func walk(_ bs: [Block]) -> String {
            bs.map { $0.id + ($0.body.map { "(" + walk($0) + ")" } ?? "") }.joined(separator: " ")
        }
        return walk(s[0].steps)
    }

    func testInsertSlots() {
        var s = scripts()
        XCTAssertTrue(ScriptTree.insert(b("n1"), at: .scriptTop("s1"), in: &s))
        XCTAssertTrue(ScriptTree.insert(b("n2"), at: .after("in1"), in: &s))
        XCTAssertTrue(ScriptTree.insert(b("n3"), at: .bodyTop("loop"), in: &s))
        XCTAssertEqual(ids(s), "n1 a loop(n3 in1 n2 in2) log")
    }

    func testMoveOutOfLoopAndIntoItselfRefused() {
        var s = scripts()
        let inner = MenuTreeSafe.find("in2", s)!
        XCTAssertTrue(ScriptTree.move(inner, to: .after("a"), in: &s))
        XCTAssertEqual(ids(s), "a in2 loop(in1) log")
        let loop = MenuTreeSafe.find("loop", s)!
        XCTAssertFalse(ScriptTree.move(loop, to: .bodyTop("loop"), in: &s), "can't drop a block inside itself")
        XCTAssertEqual(ids(s), "a in2 loop(in1) log", "a refused move changes nothing")
    }

    func testReportersInSlots() {
        var s = scripts()
        let join = MenuTreeSafe.find("join", s)!
        XCTAssertTrue(ScriptTree.setInput(join, into: "loop", slot: "times", in: &s))
        XCTAssertEqual(MenuTreeSafe.find("log", s)?.inputs["text"]?.literalValue, "", "old slot falls back to an empty value")
        XCTAssertEqual(MenuTreeSafe.find("loop", s)?.inputs["times"]?.id, "join")
        XCTAssertEqual(ScriptTree.remove("join", from: &s)?.op, "op.join")
        XCTAssertEqual(MenuTreeSafe.find("loop", s)?.inputs["times"]?.literalValue, "")
    }

    func testNamesForDropdowns() {
        var set = BlockSpec.spec("var.set")!.make(); set.fields["name"] = "hp"
        var gauge = BlockSpec.spec("looks.gauge")!.make(); gauge.inputs["name"] = .literal("Kirito")
        let s = [Script(trigger: b("h", "ext.started"), steps: [set, gauge])]
        XCTAssertEqual(ScriptTree.variableNames(s), ["hp"])
        XCTAssertEqual(ScriptTree.gaugeNames(s), ["Kirito"])
    }
}

/// Test helper: find a block anywhere by id.
enum MenuTreeSafe {
    static func find(_ id: String, _ scripts: [Script]) -> Block? {
        scripts.flatMap(\.allBlocks).first { $0.id == id }
    }
}
