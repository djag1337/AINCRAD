import XCTest
@testable import AINCRAD

final class MenuTreeTests: XCTestCase {
    func item(_ id: String, _ children: [MenuItem]? = nil) -> MenuItem {
        MenuItem(id: id, name: id, action: children == nil ? .url("https://\(id).example") : nil, children: children)
    }

    var tree: [MenuItem] { [item("a", [item("a1"), item("a2", [item("a2x")])]), item("b"), item("c")] }

    func names(_ items: [MenuItem]) -> String {
        items.map { $0.id + ($0.children.map { "(" + names($0) + ")" } ?? "") }.joined(separator: " ")
    }

    func testFindAndPath() {
        XCTAssertEqual(MenuTree.path(of: "a2x", in: tree), [0, 1, 0])
        XCTAssertEqual(MenuTree.find("a2x", in: tree)?.name, "a2x")
        XCTAssertNil(MenuTree.path(of: "zz", in: tree))
    }

    func testInsertSiblingAndChild() {
        var t = tree
        MenuTree.insert(item("n"), after: "a1", in: &t)
        MenuTree.insert(item("k"), inside: "b", in: &t)
        MenuTree.insert(item("end"), after: nil, in: &t)
        XCTAssertEqual(names(t), "a(a1 n a2(a2x)) b(k) c end")
        XCTAssertNil(MenuTree.find("b", in: t)?.action, "a parent's own action is dropped")
    }

    func testRemoveAndDuplicate() {
        var t = tree
        XCTAssertEqual(MenuTree.remove("a2", in: &t)?.children?.count, 1)
        XCTAssertEqual(names(t), "a(a1) b c")
        var u = tree
        let copy = MenuTree.duplicate("a", in: &u)!
        XCTAssertEqual(u.count, 4)
        XCTAssertEqual(u[1].name, "a Copy")
        XCTAssertNotEqual(u[1].children?[1].children?[0].id, "a2x", "nested ids are renewed")
        XCTAssertEqual(Set(MenuTree.allIDs(u)).count, MenuTree.allIDs(u).count, "no duplicate ids")
        XCTAssertEqual(u[1].id, copy)
    }

    func testMove() {
        var t = tree
        XCTAssertTrue(MenuTree.move("c", by: -1, in: &t))
        XCTAssertFalse(MenuTree.move("a", by: -1, in: &t))
        XCTAssertTrue(MenuTree.move("a1", by: 1, in: &t))
        XCTAssertEqual(names(t), "a(a2(a2x) a1) c b")
    }

    func testIndentOutdent() {
        var t = tree
        XCTAssertTrue(MenuTree.indent("b", in: &t))
        XCTAssertEqual(names(t), "a(a1 a2(a2x) b) c")
        XCTAssertFalse(MenuTree.indent("a", in: &t), "first item has no previous sibling")
        XCTAssertTrue(MenuTree.outdent("a2x", in: &t))
        XCTAssertEqual(names(t), "a(a1 a2() a2x b) c")
        XCTAssertFalse(MenuTree.outdent("c", in: &t), "already at the root")
    }

    func testIndentIntoProviderIsRefused() {
        var t = [MenuItem(id: "apps", name: "Apps", provider: "applications"), item("x")]
        XCTAssertFalse(MenuTree.indent("x", in: &t))
    }
}
