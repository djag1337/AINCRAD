import Foundation

/// Append-only log in ~/Library/Application Support/AINCRAD/logs/aincrad.log (reset past 1 MB).
enum Log {
    private static let queue = DispatchQueue(label: "aincrad.log")
    private static let formatter = ISO8601DateFormatter()
    private static let handle: FileHandle? = {
        // Unit tests deliberately feed in broken files; keep that out of the real log.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return nil }
        let dir = ConfigStore.baseDirectory.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("aincrad.log")
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
            try? FileManager.default.removeItem(at: url)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        return h
    }()

    static var fileURL: URL { ConfigStore.baseDirectory.appendingPathComponent("logs/aincrad.log") }

    static func info(_ message: String) { write("INFO", message) }
    static func error(_ message: String) { write("ERROR", message) }

    private static func write(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
        queue.async { handle?.write(Data(line.utf8)) }
    }
}
