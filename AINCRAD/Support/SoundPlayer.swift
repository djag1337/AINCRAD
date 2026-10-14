import AVFoundation
import AudioToolbox

/// Plays theme sounds through System Sound Services: playback is asynchronous and nearly free on
/// the calling thread (NSSound.play measured 10–20 ms of main-thread time per play here), and
/// nothing runs between plays. Volume is applied by writing a pre-scaled copy of each sound to
/// the cache folder, since system sounds have no per-sound volume. They also scale with the
/// alert volume in System Settings › Sound.
final class SoundPlayer {
    static let shared = SoundPlayer()

    var enabled = true
    var sounds = Theme.Sounds() {
        didSet { if sounds != oldValue { unload() } }
    }

    enum Event { case open, select, back, close, hover, error }

    private var ids: [String: SystemSoundID] = [:]
    private let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AINCRAD/sounds", isDirectory: true)

    func play(_ event: Event) {
        guard enabled, sounds.volume > 0 else { return }
        let spec = self.spec(event)
        guard !spec.isEmpty, let id = load(spec) else { return }
        AudioServicesPlaySystemSoundWithCompletion(id, nil)
    }

    /// Loads (and volume-scales) every sound up front so the first play has no setup cost.
    func prewarm() {
        guard enabled else { return }
        [Event.open, .select, .back, .close, .hover, .error].map(spec).filter { !$0.isEmpty }.forEach { _ = load($0) }
    }

    private func spec(_ event: Event) -> String {
        switch event {
        case .open: return sounds.open
        case .select: return sounds.select
        case .back: return sounds.back
        case .close: return sounds.close
        case .hover: return sounds.hover
        case .error: return sounds.error
        }
    }

    private func load(_ spec: String) -> SystemSoundID? {
        if let id = ids[spec] { return id }
        let source: URL?
        if spec.hasPrefix("builtin:") {
            source = Bundle.main.url(forResource: String(spec.dropFirst(8)), withExtension: "wav")
        } else {
            let path = (spec as NSString).expandingTildeInPath
            source = FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        guard let source, let scaled = scaledCopy(of: source) else {
            Log.error("sound not found or unreadable: \(spec)")
            return nil
        }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(scaled as CFURL, &id) == noErr else {
            Log.error("sound could not be registered: \(spec)")
            return nil
        }
        ids[spec] = id
        return id
    }

    private func scaledCopy(of url: URL) -> URL? {
        let volume = Float(min(max(sounds.volume, 0), 1))
        // Stable across launches (String.hashValue is not): name + modification time + volume.
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.deletingPathExtension().lastPathComponent)-\(Int(mtime))-\(Int(volume * 100)).caf"
        let out = cacheDir.appendingPathComponent(key)
        if FileManager.default.fileExists(atPath: out.path) { return out }
        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: buffer)
            if let channels = buffer.floatChannelData {
                for c in 0..<Int(buffer.format.channelCount) {
                    for i in 0..<Int(buffer.frameLength) { channels[c][i] *= volume }
                }
            }
            let writer = try AVAudioFile(forWriting: out, settings: file.processingFormat.settings)
            try writer.write(from: buffer)
            return out
        } catch {
            Log.error("sound \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private func unload() {
        ids.values.forEach { AudioServicesDisposeSystemSoundID($0) }
        ids = [:]
    }
}
