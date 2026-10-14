import XCTest
@testable import AINCRAD

final class SettingsModelTests: XCTestCase {
    var dir: URL!
    var model: SettingsModel!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ConfigStore(directory: dir)
        store.load()
        let noop = AppActions(applySettings: {}, reloadAll: { store.load() }, previewMenu: { _, _ in },
                              suspendHotKeys: { _ in }, requestAccessibility: {}, hasAccessibility: { false })
        model = SettingsModel(store: store, actions: noop, widgets: WidgetManager(store: store), extensions: ExtensionManager(store: store))
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testEditUndoRedoTracksDirtyAgainstDisk() {
        XCTAssertFalse(model.menuDirty)
        model.selectedItemID = model.menu.root[0].id
        model.addItem(submenu: false)
        XCTAssertTrue(model.menuDirty)
        model.undoMenu()
        XCTAssertFalse(model.menuDirty, "undoing to the saved state is clean")
        model.redoMenu()
        XCTAssertTrue(model.menuDirty)
    }

    func testRenameCoalescesIntoOneUndoStep() {
        var item = model.menu.root[0]
        model.selectedItemID = item.id
        for name in ["F", "Fa", "Fav", "Favs"] {
            item.name = name
            model.updateSelected(item, field: "name")
        }
        XCTAssertEqual(model.menu.root[0].name, "Favs")
        model.undoMenu()
        XCTAssertEqual(model.menu.root[0].name, "Favorites")
        XCTAssertFalse(model.canUndoMenu)
    }

    func testSaveWritesFileAndBackup() throws {
        model.selectedItemID = model.menu.root.last!.id
        model.addItem(submenu: true)
        model.saveMenu()
        XCTAssertFalse(model.menuDirty)
        let onDisk = try JSONDecoder().decode(MenuFile.self, from: Data(contentsOf: model.store.menuURL))
        XCTAssertEqual(onDisk.root.last?.children?.last?.name, "New Menu", "added inside the selected submenu")
        let backups = try FileManager.default.contentsOfDirectory(atPath: model.store.backupsURL.path)
        XCTAssertTrue(backups.contains { $0.hasPrefix("menu-") })
    }

    func testThemeDuplicateEditSaveAndImportValidation() throws {
        model.duplicateTheme()
        XCTAssertEqual(model.editingThemeID, "aincrad-classic-copy")
        model.editTheme { $0.colors.accent = "#FF0000" }
        XCTAssertTrue(model.themeDirty)
        model.saveTheme()
        XCTAssertEqual(model.store.loadTheme("aincrad-classic-copy").colors.accent, "#FF0000")

        let bad = dir.appendingPathComponent("bad.json")
        try Data(#"{"colors": "nope"}"#.utf8).write(to: bad)
        XCTAssertThrowsError(try model.store.importTheme(from: bad))
        XCTAssertFalse(model.store.themeIDs().contains("bad"), "a rejected import leaves nothing behind")
    }
}
