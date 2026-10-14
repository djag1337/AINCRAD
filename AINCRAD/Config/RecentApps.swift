import AppKit

/// Remembers which apps you switch to (most recent first) for the "recentApps" menu provider.
/// Event-driven via NSWorkspace notifications; saved with a short debounce, never polled.
final class RecentApps {
    private let url: URL
    private let limit = 15
    private(set) var paths: [String] = []
    private var observer: NSObjectProtocol?
    private var saveWork: DispatchWorkItem?

    init(directory: URL) {
        url = directory.appendingPathComponent("recents.json")
        if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([String].self, from: data) {
            paths = list
        }
    }

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular, app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  let path = app.bundleURL?.path else { return }
            self?.note(path)
        }
    }

    func note(_ path: String) {
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > limit { paths.removeLast(paths.count - limit) }
        scheduleSave()
    }

    func items() -> [MenuItem] {
        paths.filter { FileManager.default.fileExists(atPath: $0) }
            .map { MenuItem(id: "recent:" + $0, name: AppScanner.displayName($0), action: .app($0)) }
    }

    func save() {
        saveWork?.cancel()
        try? JSONEncoder().encode(paths).write(to: url, options: .atomic)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
}
