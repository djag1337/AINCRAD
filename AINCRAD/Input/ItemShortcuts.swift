import Foundation

/// Registers a global hotkey for every menu item that has a `shortcut`, so items can be run
/// without opening the launcher.
final class ItemShortcuts {
    private var keys: [HotKey] = []
    private(set) var problems: [String] = []

    func register(_ menu: MenuFile, run: @escaping (MenuItem) -> Void) {
        keys = []
        problems = []
        func walk(_ items: [MenuItem]) {
            for item in items {
                if let text = item.shortcut, !text.isEmpty, item.action != nil {
                    if let spec = HotKey.parse(text), let key = HotKey(spec, handler: { run(item) }) {
                        keys.append(key)
                    } else {
                        problems.append("Shortcut \"\(text)\" for \(item.name) is invalid or taken")
                    }
                }
                walk(item.children ?? [])
            }
        }
        walk(menu.root)
        if !keys.isEmpty { Log.info("registered \(keys.count) item shortcuts") }
        problems.forEach { Log.error($0) }
    }

    func unregister() { keys = [] }
}
