import Foundation

/// Edits on a set of scripts, addressed by block id: what drag and drop in the Studio does.
enum ScriptTree {
    enum Slot: Equatable {
        case scriptTop(String)  // first step of a script (after its event block)
        case after(String)      // right after a statement
        case bodyTop(String)    // first statement inside a C-block
        case elseTop(String)    // first statement inside an if/else's else part
    }

    /// Removes a block anywhere. A reporter removed from a slot leaves an empty literal behind.
    @discardableResult
    static func remove(_ id: String, from scripts: inout [Script]) -> Block? {
        for i in scripts.indices {
            if let b = remove(id, in: &scripts[i].steps) { return b }
            if let b = removeInput(id, in: &scripts[i].trigger) { return b }
        }
        return nil
    }

    private static func remove(_ id: String, in blocks: inout [Block]) -> Block? {
        for i in blocks.indices {
            if blocks[i].id == id { return blocks.remove(at: i) }
            if let b = removeInput(id, in: &blocks[i]) { return b }
            if var body = blocks[i].body, let b = remove(id, in: &body) { blocks[i].body = body; return b }
            if var e = blocks[i].elseBody, let b = remove(id, in: &e) { blocks[i].elseBody = e; return b }
        }
        return nil
    }

    private static func removeInput(_ id: String, in block: inout Block) -> Block? {
        for key in block.inputs.keys.sorted() {
            guard var input = block.inputs[key] else { continue }
            if input.id == id {
                block.inputs[key] = .literal("")
                return input
            }
            if let b = removeInput(id, in: &input) { block.inputs[key] = input; return b }
        }
        return nil
    }

    /// Applies `change` to the block with `id`. Returns false if it isn't found.
    @discardableResult
    static func mutate(_ id: String, in scripts: inout [Script], _ change: (inout Block) -> Void) -> Bool {
        for i in scripts.indices {
            if mutate(id, in: &scripts[i].trigger, change) { return true }
            for j in scripts[i].steps.indices where mutate(id, in: &scripts[i].steps[j], change) { return true }
        }
        return false
    }

    private static func mutate(_ id: String, in block: inout Block, _ change: (inout Block) -> Void) -> Bool {
        if block.id == id { change(&block); return true }
        for key in block.inputs.keys.sorted() {
            guard var input = block.inputs[key] else { continue }
            if mutate(id, in: &input, change) { block.inputs[key] = input; return true }
        }
        if var body = block.body {
            for j in body.indices where mutate(id, in: &body[j], change) { block.body = body; return true }
        }
        if var e = block.elseBody {
            for j in e.indices where mutate(id, in: &e[j], change) { block.elseBody = e; return true }
        }
        return false
    }

    @discardableResult
    static func insert(_ new: Block, at slot: Slot, in scripts: inout [Script]) -> Bool {
        switch slot {
        case .scriptTop(let sid):
            guard let i = scripts.firstIndex(where: { $0.id == sid }) else { return false }
            scripts[i].steps.insert(new, at: 0)
            return true
        case .after(let id):
            for i in scripts.indices where insert(new, after: id, in: &scripts[i].steps) { return true }
            return false
        case .bodyTop(let id):
            return mutate(id, in: &scripts) { $0.body = [new] + ($0.body ?? []) }
        case .elseTop(let id):
            return mutate(id, in: &scripts) { $0.elseBody = [new] + ($0.elseBody ?? []) }
        }
    }

    private static func insert(_ new: Block, after id: String, in blocks: inout [Block]) -> Bool {
        for i in blocks.indices {
            if blocks[i].id == id { blocks.insert(new, at: i + 1); return true }
            if var body = blocks[i].body, insert(new, after: id, in: &body) { blocks[i].body = body; return true }
            if var e = blocks[i].elseBody, insert(new, after: id, in: &e) { blocks[i].elseBody = e; return true }
        }
        return false
    }

    /// Moves or places a dragged block. Refuses to drop a block into itself.
    @discardableResult
    static func move(_ block: Block, to slot: Slot, in scripts: inout [Script]) -> Bool {
        let target: String
        switch slot {
        case .scriptTop(let s): target = s
        case .after(let id), .bodyTop(let id), .elseTop(let id): target = id
        }
        if block.all.contains(where: { $0.id == target }) { return false }
        var copy = scripts
        remove(block.id, from: &copy)
        guard insert(block, at: slot, in: &copy) else { return false }
        scripts = copy
        return true
    }

    /// Puts a reporter into a value slot (moving it if it was already somewhere).
    @discardableResult
    static func setInput(_ reporter: Block, into id: String, slot name: String, in scripts: inout [Script]) -> Bool {
        if reporter.all.contains(where: { $0.id == id }) { return false }
        var copy = scripts
        remove(reporter.id, from: &copy)
        guard mutate(id, in: &copy, { $0.inputs[name] = reporter }) else { return false }
        scripts = copy
        return true
    }

    /// Variable names used anywhere, for the variable dropdowns.
    static func variableNames(_ scripts: [Script]) -> [String] {
        Array(Set(scripts.flatMap(\.allBlocks).filter { BlockSpec.variableOps.contains($0.op) }.compactMap { $0.fields["name"] }))
            .filter { !$0.isEmpty }.sorted()
    }

    /// Gauge names set by "set gauge" blocks with a literal name.
    static func gaugeNames(_ scripts: [Script]) -> [String] {
        Array(Set(scripts.flatMap(\.allBlocks).filter { $0.op == "looks.gauge" }.compactMap { $0.inputs["name"]?.literalValue }))
            .filter { !$0.isEmpty }.sorted()
    }
}
