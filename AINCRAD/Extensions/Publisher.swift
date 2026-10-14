import Foundation

/// Publishes an extension folder or a theme into the user's catalog repository: copy into
/// src/, run the catalog build (packages, previews, checksums), commit and push.
/// Everything runs as child processes in the background; progress lines go to `log`.
enum Publisher {
    enum Item {
        case extensionFolder(URL, id: String, name: String, version: String)
        case theme(Theme, id: String)
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func repoURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// Runs the whole flow; returns the catalog's web page on success.
    static func publish(_ item: Item, repo: URL, log: @escaping (String) -> Void) throws -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: repo.appendingPathComponent("tools/build_catalog.py").path) else {
            throw Failure(message: "No catalog repository at \(repo.path) (expected tools/build_catalog.py).")
        }
        let summary: String
        switch item {
        case .extensionFolder(let folder, let id, let name, let version):
            let dest = repo.appendingPathComponent("src/extensions/\(id)")
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: folder, to: dest)
            summary = "\(name) \(version)"
            log("copied \(id) into src/extensions")
        case .theme(let theme, let id):
            let dest = repo.appendingPathComponent("src/themes/\(id).json")
            try ConfigStore.themeData(theme).write(to: dest, options: .atomic)
            summary = "theme \(theme.name)"
            log("copied \(id).json into src/themes")
        }
        log(try run("/usr/bin/python3", ["tools/build_catalog.py"], in: repo))
        _ = try run("/usr/bin/git", ["add", "-A"], in: repo)
        let status = try run("/usr/bin/git", ["status", "--porcelain"], in: repo)
        if status.isEmpty {
            log("nothing changed since the last publish")
        } else {
            log(try run("/usr/bin/git", ["commit", "-q", "-m", "Publish \(summary)"], in: repo))
            log("pushing…")
            log(try run("/usr/bin/git", ["push", "-q"], in: repo))
        }
        let remote = (try? run("/usr/bin/git", ["remote", "get-url", "origin"], in: repo)) ?? ""
        let page = remote.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".git", with: "")
        log("published \(summary)")
        return page
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String], in dir: URL) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.currentDirectoryURL = dir
        // Never prompt for credentials in a hidden terminal: fail with a message instead.
        p.environment = ProcessInfo.processInfo.environment.merging(["GIT_TERMINAL_PROMPT": "0"]) { $1 }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard p.terminationStatus == 0 else {
            throw Failure(message: "\(URL(fileURLWithPath: tool).lastPathComponent) \(args.first ?? "") failed: \(text)")
        }
        return text
    }
}
