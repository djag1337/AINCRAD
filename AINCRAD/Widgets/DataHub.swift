import Foundation
import IOKit.ps

struct StatSample {
    /// 0…1 when the source has a natural fill level (usage, charge); nil for rates like network.
    var fraction: Double?
    /// Short readout, e.g. "37%" or "5.1 / 8 GB".
    var text: String
    var used: Double? = nil
    var total: Double? = nil
}

enum StatSource: String, CaseIterable {
    case cpu, memory, disk, battery, network, uptime

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .battery: return "Battery"
        case .network: return "Network"
        case .uptime: return "Uptime"
        }
    }

    /// Seconds between samples: as slow as the value is useful.
    var interval: TimeInterval {
        switch self {
        case .cpu, .network: return 2
        case .memory: return 5
        case .battery: return 30
        case .disk, .uptime: return 60
        }
    }
}

/// Shared system readings. Each source runs one timer, only while at least one visible widget
/// subscribes to it; with no subscribers nothing is sampled.
final class DataHub {
    static let shared = DataHub()
    init() {}

    final class Token {
        fileprivate let key: String
        fileprivate let id = UUID()
        fileprivate init(_ key: String) { self.key = key }
    }

    /// A source added by an extension: sampled asynchronously, at its own interval.
    struct ExternalSource {
        var title: String
        var interval: TimeInterval
        var fetch: (@escaping (StatSample?) -> Void) -> Void
    }

    private var handlers: [String: [UUID: (StatSample) -> Void]] = [:]
    private var timers: [String: Timer] = [:]
    private(set) var latest: [String: StatSample] = [:]
    private(set) var external: [String: ExternalSource] = [:]
    private let host = mach_host_self()
    private var lastCPU: [UInt32]?
    private var lastCPUSample: StatSample?
    private var lastNet: (rx: UInt64, tx: UInt64, time: TimeInterval)?

    var activeSources: [String] { Array(timers.keys) }

    func register(_ key: String, _ source: ExternalSource) { external[key] = source }

    func unregisterAll(prefix: String) {
        external.keys.filter { $0.hasPrefix(prefix) }.forEach { external[$0] = nil }
    }

    func title(for key: String) -> String {
        StatSource(rawValue: key)?.title ?? external[key]?.title ?? gaugeTitles[key] ?? key
    }

    /// Script gauges ("script:<extension>/<name>") are pushed by scripts rather than sampled.
    private(set) var gaugeTitles: [String: String] = [:]

    func push(_ key: String, title: String, _ sample: StatSample) {
        gaugeTitles[key] = title
        deliver(key, sample)
    }

    func subscribe(_ source: StatSource, _ handler: @escaping (StatSample) -> Void) -> Token {
        subscribe(key: source.rawValue, handler)
    }

    func subscribe(key: String, _ handler: @escaping (StatSample) -> Void) -> Token {
        let token = Token(key)
        handlers[key, default: [:]][token.id] = handler
        if key.hasPrefix("script:") {
            if let sample = latest[key] { handler(sample) }
        } else if timers[key] == nil {
            let interval = StatSource(rawValue: key)?.interval ?? external[key]?.interval ?? 60
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick(key) }
            t.tolerance = interval * 0.2 // lets macOS coalesce wake-ups
            RunLoop.main.add(t, forMode: .common)
            timers[key] = t
            tick(key)
        } else if let sample = latest[key] {
            handler(sample)
        }
        return token
    }

    func unsubscribe(_ token: Token) {
        handlers[token.key]?[token.id] = nil
        if handlers[token.key]?.isEmpty ?? true {
            timers[token.key]?.invalidate()
            timers[token.key] = nil
            if token.key == StatSource.cpu.rawValue { lastCPU = nil }
            if token.key == StatSource.network.rawValue { lastNet = nil }
        }
    }

    private func tick(_ key: String) {
        if let source = StatSource(rawValue: key) {
            if let sample = sample(source) { deliver(key, sample) }
        } else if let ext = external[key] {
            ext.fetch { [weak self] sample in
                DispatchQueue.main.async { if let sample { self?.deliver(key, sample) } }
            }
        }
    }

    private func deliver(_ key: String, _ sample: StatSample) {
        latest[key] = sample
        handlers[key]?.values.forEach { $0(sample) }
    }

    func sample(_ source: StatSource) -> StatSample? {
        switch source {
        case .cpu: return cpu()
        case .memory: return memory()
        case .disk: return disk()
        case .battery: return battery()
        case .network: return network()
        case .uptime:
            let s = Int(ProcessInfo.processInfo.systemUptime)
            let text = s >= 86_400 ? "\(s / 86_400)d \(s % 86_400 / 3600)h" : "\(s / 3600)h \(s % 3600 / 60)m"
            return StatSample(fraction: nil, text: text, used: Double(s), total: nil)
        }
    }

    // MARK: Sources

    private func cpu() -> StatSample? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return nil }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3] // user, system, idle, nice
        defer { lastCPU = ticks }
        guard let last = lastCPU else { return StatSample(fraction: 0, text: "…") }
        let d = zip(ticks, last).map { Double($0 &- $1) }
        let total = d.reduce(0, +)
        guard total > 0 else { return lastCPUSample ?? StatSample(fraction: 0, text: "…") }
        let busy = (d[0] + d[1] + d[3]) / total
        let sample = StatSample(fraction: busy, text: "\(Int((busy * 100).rounded()))%", used: busy * 100, total: 100)
        lastCPUSample = sample
        return sample
    }

    private func memory() -> StatSample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return nil }
        let page = Double(vm_kernel_page_size)
        // Activity Monitor's "Memory Used": app memory + wired + compressed.
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let used = (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return StatSample(fraction: min(used / total, 1), text: "\(gb(used)) / \(gb(total)) GB", used: used, total: total)
    }

    private func disk() -> StatSample? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        let used = Double(total) - Double(free)
        return StatSample(fraction: used / Double(total), text: "\(gb(used, digits: 0)) / \(gb(Double(total), digits: 0)) GB",
                          used: used, total: Double(total))
    }

    private func battery() -> StatSample? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return StatSample(fraction: nil, text: "AC power")
        }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = (d[kIOPSIsChargingKey] as? Bool) == true
            return StatSample(fraction: Double(cur) / Double(max), text: "\(cur * 100 / max)%\(charging ? " ⚡︎" : "")",
                              used: Double(cur), total: Double(max))
        }
        return StatSample(fraction: nil, text: "AC power")
    }

    private func network() -> StatSample? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = a.ifa_data else { continue }
            let name = String(cString: a.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(d.ifi_ibytes)
            tx += UInt64(d.ifi_obytes)
        }
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastNet = (rx, tx, now) }
        guard let last = lastNet, now > last.time, rx >= last.rx, tx >= last.tx else { return StatSample(fraction: nil, text: "↓ … ↑ …") }
        let dt = now - last.time
        let down = Double(rx - last.rx) / dt, up = Double(tx - last.tx) / dt
        return StatSample(fraction: nil, text: "↓ \(rate(down))  ↑ \(rate(up))", used: down, total: nil)
    }

    private func gb(_ bytes: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", bytes / 1_073_741_824)
    }

    private func rate(_ bytesPerSecond: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
}
