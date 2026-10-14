import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A zipped extension folder; double-clicking installs it.
    static let aincradPackage = UTType(exportedAs: "com.djag.aincrad.package", conformingTo: .zip)
}

enum Packages {
    enum PackageError: LocalizedError {
        case unsafe(String), invalid(String), tool(String)
        var errorDescription: String? {
            switch self {
            case .unsafe(let m): return "Refused an unsafe package: \(m)"
            case .invalid(let m): return "Not a valid AINCRAD extension: \(m)"
            case .tool(let m): return m
            }
        }
    }

    static func zip(_ folder: URL, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--keepParent", folder.path, url.path])
    }

    /// Unpacks into a fresh temporary folder after checking every entry name, then validates
    /// the manifest. Returns the folder that contains extension.json.
    static func unpack(_ url: URL) throws -> (folder: URL, manifest: ExtensionManifest) {
        let listing = try run("/usr/bin/zipinfo", ["-1", url.path])
        for name in listing.split(separator: "\n").map(String.init) {
            if name.hasPrefix("/") || name.split(separator: "/").contains("..") { throw PackageError.unsafe("entry \"\(name)\"") }
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("aincrad-pkg-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", "--norsrc", url.path, tmp.path])
        let items = FileManager.default.enumerator(at: tmp, includingPropertiesForKeys: [.isSymbolicLinkKey])?.allObjects as? [URL] ?? []
        if items.contains(where: { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true }) {
            throw PackageError.unsafe("it contains symbolic links")
        }
        let manifests = items.filter { $0.lastPathComponent == "extension.json" && !$0.path.contains("__MACOSX") }
        guard let manifestURL = manifests.min(by: { $0.pathComponents.count < $1.pathComponents.count }) else {
            throw PackageError.invalid("no extension.json inside")
        }
        let manifest: ExtensionManifest
        do { manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: manifestURL)) }
        catch { throw PackageError.invalid(TolerantJSON.describe(error)) }
        if let problem = ExtensionManager.validate(manifest) { throw PackageError.invalid(problem) }
        return (manifestURL.deletingLastPathComponent(), manifest)
    }

    /// Copies an unpacked extension into Extensions/<id>, replacing an older copy. It stays
    /// disabled until the user enables it (and approves its permissions).
    static func install(_ unpacked: URL, id: String, into extensionsFolder: URL) throws -> URL {
        let dest = extensionsFolder.appendingPathComponent(id, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: extensionsFolder, withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: unpacked, to: dest)
        return dest
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PackageError.tool("\(URL(fileURLWithPath: tool).lastPathComponent) failed: \(msg.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
