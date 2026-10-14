import AppKit

/// Detects crash loops: a marker file exists while AINCRAD runs and is removed on a clean quit.
/// Two unclean exits in a row, each within a minute of launch, start the next launch in safe
/// mode (no gesture, widgets, item shortcuts or extensions). Holding ⌥ at launch does the same.
final class LaunchGuard {
    struct State: Codable { var rapidCrashes = 0 }

    private let marker: URL
    private let stateURL: URL
    private(set) var safeMode = false
    private(set) var reason = ""

    init(directory: URL) {
        marker = directory.appendingPathComponent(".running")
        stateURL = directory.appendingPathComponent("launch-state.json")
    }

    func begin() {
        try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        var state = (try? JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))) ?? State()
        switch try? String(contentsOf: marker, encoding: .utf8) {
        case "starting"?:
            state.rapidCrashes += 1
            Log.error("previous run ended within a minute of launch without a clean quit (\(state.rapidCrashes) in a row)")
        case "stable"?:
            state.rapidCrashes = 0
            Log.error("previous run ended without a clean quit")
        default:
            state.rapidCrashes = 0
        }
        if NSEvent.modifierFlags.contains(.option) {
            safeMode = true
            reason = "⌥ was held at launch"
        } else if state.rapidCrashes >= 2 {
            safeMode = true
            reason = "AINCRAD quit unexpectedly twice right after starting"
        }
        if safeMode { Log.error("SAFE MODE: \(reason)") }
        try? JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        writeMarker()
        // Recorded so the next launch can tell a quick crash from a long session.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.markStable() }
    }

    /// Called on a clean quit.
    func end() {
        try? FileManager.default.removeItem(at: marker)
        try? JSONEncoder().encode(State()).write(to: stateURL, options: .atomic)
    }

    private func writeMarker() {
        try? Data("starting".utf8).write(to: marker, options: .atomic)
    }

    private func markStable() {
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        try? Data("stable".utf8).write(to: marker, options: .atomic)
    }

    private func lastRunShort() -> Bool {
        (try? String(contentsOf: marker, encoding: .utf8)) == "starting"
    }
}
