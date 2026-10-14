import Foundation

/// Structural edits on a menu tree, addressed by item id. Pure value operations so the editor
/// can snapshot them for undo and the tests can check every case.
enum MenuTree {
    static func path(of id: String, in items: [MenuItem]) -> [Int]? {
        for (i, item) in items.enumerated() {
            if item.id == id { return [i] }
            if let children = item.children, let sub = path(of: id, in: children) { return [i] + sub }
        }
        return nil
    }

    static func item(at path: [Int], in items: [MenuItem]) -> MenuItem? {
        guard let first = path.first, items.indices.contains(first) else { return nil }
        return path.count == 1 ? items[first] : item(at: Array(path.dropFirst()), in: items[first].children ?? [])
    }

    static func find(_ id: String, in items: [MenuItem]) -> MenuItem? {
        path(of: id, in: items).flatMap { item(at: $0, in: items) }
    }

    /// Runs `body` on the sibling array that contains `path`'s last index.
    private static func withSiblings(of path: [Int], in items: inout [MenuItem], _ body: (inout [MenuItem], Int) -> Void) {
        guard let first = path.first else { return }
        if path.count == 1 { return body(&items, first) }
        guard items.indices.contains(first) else { return }
        var children = items[first].children ?? []
        withSiblings(of: Array(path.dropFirst()), in: &children, body)
        items[first].children = children
    }

    static func replace(_ item: MenuItem, in items: inout [MenuItem]) {
        guard let p = path(of: item.id, in: items) else { return }
        withSiblings(of: p, in: &items) { siblings, i in siblings[i] = item }
    }

    /// Inserts after `afterID` (as a sibling), or at the end of the root when nil / not found.
    static func insert(_ new: MenuItem, after afterID: String?, in items: inout [MenuItem]) {
        guard let id = afterID, let p = path(of: id, in: items) else { return items.append(new) }
        withSiblings(of: p, in: &items) { siblings, i in siblings.insert(new, at: i + 1) }
    }

    /// Appends as the last child of `parentID`, turning it into a submenu if needed.
    static func insert(_ new: MenuItem, inside parentID: String, in items: inout [MenuItem]) {
        guard var parent = find(parentID, in: items) else { return }
        parent.children = (parent.children ?? []) + [new]
        parent.action = nil
        replace(parent, in: &items)
    }

    @discardableResult
    static func remove(_ id: String, in items: inout [MenuItem]) -> MenuItem? {
        guard let p = path(of: id, in: items) else { return nil }
        var removed: MenuItem?
        withSiblings(of: p, in: &items) { siblings, i in removed = siblings.remove(at: i) }
        return removed
    }

    /// Deep copy with fresh ids, inserted right after the original. Returns the copy's id.
    @discardableResult
    static func duplicate(_ id: String, in items: inout [MenuItem]) -> String? {
        guard var copy = find(id, in: items) else { return nil }
        renew(&copy)
        copy.name += " Copy"
        insert(copy, after: id, in: &items)
        return copy.id
    }

    private static func renew(_ item: inout MenuItem) {
        item.id = UUID().uuidString
        if var children = item.children {
            for i in children.indices { renew(&children[i]) }
            item.children = children
        }
    }

    /// Moves within its sibling list by `delta` (-1 up, +1 down). Returns false at the ends.
    @discardableResult
    static func move(_ id: String, by delta: Int, in items: inout [MenuItem]) -> Bool {
        guard let p = path(of: id, in: items) else { return false }
        var moved = false
        withSiblings(of: p, in: &items) { siblings, i in
            let j = i + delta
            guard siblings.indices.contains(j) else { return }
            siblings.swapAt(i, j)
            moved = true
        }
        return moved
    }

    /// Makes the item the last child of its previous sibling (which becomes a submenu).
    @discardableResult
    static func indent(_ id: String, in items: inout [MenuItem]) -> Bool {
        guard let p = path(of: id, in: items), let last = p.last, last > 0 else { return false }
        let previous = item(at: Array(p.dropLast()) + [last - 1], in: items)
        guard let target = previous, target.provider == nil, let item = remove(id, in: &items) else { return false }
        insert(item, inside: target.id, in: &items)
        return true
    }

    /// Moves the item out of its parent, placing it right after the parent.
    @discardableResult
    static func outdent(_ id: String, in items: inout [MenuItem]) -> Bool {
        guard let p = path(of: id, in: items), p.count > 1,
              let parent = item(at: Array(p.dropLast()), in: items),
              let item = remove(id, in: &items) else { return false }
        insert(item, after: parent.id, in: &items)
        return true
    }

    /// Every item id in display order, for "is this id still present" checks.
    static func allIDs(_ items: [MenuItem]) -> [String] {
        items.flatMap { [$0.id] + allIDs($0.children ?? []) }
    }
}
