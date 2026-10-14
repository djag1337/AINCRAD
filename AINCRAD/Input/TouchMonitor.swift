import AppKit
import IOKit

/// Reads raw finger positions from Magic Mouse / trackpad surfaces through Apple's private
/// MultitouchSupport framework (the same one BetterTouchTool and MiddleClick use). It's loaded
/// with dlopen, so if a macOS update removes or changes it, AINCRAD logs that and carries on
/// without the touch gesture. Read-only: it never posts or blocks events.
final class TouchMonitor {
    private static var current: TouchMonitor?

    var onTrigger: (() -> Void)?
    private(set) var isRunning = false
    private(set) var deviceSummary = ""

    private let lock = NSLock()
    private var settings: GestureSettings
    private var launcherOpen = false
    private var recognizers: [UnsafeMutableRawPointer: TouchGestureRecognizer] = [:]
    private var devices: [UnsafeMutableRawPointer] = []
    private var deviceList: CFArray?
    private var notifyPort: IONotificationPortRef?
    private var matchIterator: io_iterator_t = 0
    private var wakeObserver: NSObjectProtocol?
    private var loggedFirstFrame = false

    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void
    private typealias Dims = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32
    private typealias Family = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>) -> Int32

    private struct API {
        let createList: CreateList, register: Register, unregister: Register, start: Start, stop: Stop, dims: Dims, family: Family
    }

    private static let api: API? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else { return nil }
        func sym<T>(_ name: String, _: T.Type) -> T? { dlsym(h, name).map { unsafeBitCast($0, to: T.self) } }
        guard let c = sym("MTDeviceCreateList", CreateList.self), let r = sym("MTRegisterContactFrameCallback", Register.self),
              let u = sym("MTUnregisterContactFrameCallback", Register.self), let s = sym("MTDeviceStart", Start.self),
              let st = sym("MTDeviceStop", Stop.self), let d = sym("MTDeviceGetSensorSurfaceDimensions", Dims.self),
              let f = sym("MTDeviceGetFamilyID", Family.self) else { return nil }
        return API(createList: c, register: r, unregister: u, start: s, stop: st, dims: d, family: f)
    }()

    static var isAvailable: Bool { api != nil }

    /// One function for register and unregister: the framework matches them by pointer.
    private static let frameCallback: Callback = { device, touches, count, timestamp, _ in
        TouchMonitor.current?.handle(device, touches, Int(count), timestamp)
        return 0
    }

    init(settings: GestureSettings) { self.settings = settings }

    func update(_ s: GestureSettings) {
        lock.lock()
        settings = s
        for key in recognizers.keys { recognizers[key]?.config = TouchMonitor.config(s) }
        lock.unlock()
    }

    func setLauncherOpen(_ open: Bool) {
        lock.lock()
        launcherOpen = open
        lock.unlock()
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard let api = TouchMonitor.api else {
            Log.error("touch gesture: MultitouchSupport isn't available on this macOS")
            return false
        }
        TouchMonitor.current = self
        attach(api)
        watchForDevices()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reattach()
        }
        isRunning = true
        return true
    }

    func stop() {
        guard isRunning, let api = TouchMonitor.api else { return }
        detach(api)
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        if matchIterator != 0 { IOObjectRelease(matchIterator); matchIterator = 0 }
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
        notifyPort = nil
        if TouchMonitor.current === self { TouchMonitor.current = nil }
        isRunning = false
        Log.info("touch gesture stopped")
    }

    // MARK: Devices

    private func attach(_ api: API) {
        guard let list = api.createList()?.takeRetainedValue() else { return }
        deviceList = list
        let all = (list as [AnyObject]).map { Unmanaged.passUnretained($0).toOpaque() }
        lock.lock()
        let includeTrackpads = settings.touchDevices == "all"
        lock.unlock()
        var kept: [String] = []
        devices = all.filter { d in
            var w: Int32 = 0, h: Int32 = 0, fam: Int32 = 0
            _ = api.dims(d, &w, &h)
            _ = api.family(d, &fam)
            // Surface size in 1/100 mm: a Magic Mouse is ~52 × 91 mm, trackpads are far wider.
            let isMouse = w > 0 && w < 7000
            let use = isMouse || includeTrackpads
            kept.append("\(isMouse ? "mouse" : "trackpad")(family \(fam), \(w / 100)×\(h / 100) mm)\(use ? "" : " ignored")")
            return use
        }
        lock.lock()
        recognizers = Dictionary(uniqueKeysWithValues: devices.map { ($0, TouchGestureRecognizer(config: TouchMonitor.config(settings))) })
        lock.unlock()
        for d in devices {
            api.register(d, TouchMonitor.frameCallback)
            api.start(d, 0)
        }
        deviceSummary = kept.isEmpty ? "no multitouch devices" : kept.joined(separator: ", ")
        Log.info("touch gesture: \(deviceSummary)")
    }

    private func detach(_ api: API) {
        for d in devices {
            api.unregister(d, TouchMonitor.frameCallback)
            api.stop(d)
        }
        devices = []
        deviceList = nil
        lock.lock()
        recognizers = [:]
        lock.unlock()
    }

    private func reattach() {
        guard isRunning, let api = TouchMonitor.api else { return }
        detach(api)
        attach(api)
    }

    /// A Magic Mouse that (re)connects shows up as a new AppleMultitouchDevice; re-scan then.
    private func watchForDevices() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, .main)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let matched: IOServiceMatchingCallback = { refcon, iterator in
            while case let obj = IOIteratorNext(iterator), obj != 0 { IOObjectRelease(obj) }
            guard let refcon else { return }
            let monitor = Unmanaged<TouchMonitor>.fromOpaque(refcon).takeUnretainedValue()
            // Give the driver a moment before re-scanning.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { monitor.reattach() }
        }
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("AppleMultitouchDevice"),
                                         matched, refcon, &matchIterator)
        while case let obj = IOIteratorNext(matchIterator), obj != 0 { IOObjectRelease(obj) } // arm the notification
    }

    // MARK: Frames (MultitouchSupport's thread)

    /// Layout of MultitouchSupport's per-finger record (96 bytes): identifier at 16, state at 20,
    /// normalised x/y at 32/36. States 3–5 mean the finger is on the surface.
    private static let stride = 96

    private func handle(_ device: UnsafeMutableRawPointer?, _ touches: UnsafeMutableRawPointer?, _ count: Int, _ time: Double) {
        guard let device else { return }
        var list: [TouchGestureRecognizer.Touch] = []
        if let touches {
            for i in 0..<count {
                let p = touches + i * TouchMonitor.stride
                let state = p.load(fromByteOffset: 20, as: Int32.self)
                guard (3...5).contains(state) else { continue }
                list.append(.init(id: p.load(fromByteOffset: 16, as: Int32.self),
                                  x: p.load(fromByteOffset: 32, as: Float.self),
                                  y: p.load(fromByteOffset: 36, as: Float.self)))
            }
        }
        lock.lock()
        guard var r = recognizers[device] else { lock.unlock(); return }
        let open = launcherOpen
        let fired = r.frame(list, time: time) && !open
        let travel = r.lastTravel
        recognizers[device] = r
        let first = !loggedFirstFrame
        loggedFirstFrame = true
        lock.unlock()
        if first { Log.info("touch gesture: receiving touch frames") }
        if fired {
            Log.info(String(format: "touch gesture fired (travel dx %.2f dy %.2f)", travel.dx, travel.dy))
            DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
        }
    }

    private static func config(_ s: GestureSettings) -> TouchGestureRecognizer.Config {
        TouchGestureRecognizer.Config(fingers: s.touchFingers, distance: Float(s.touchDistance), maxTime: 0.8,
                                      direction: s.slide == "none" ? "down" : s.slide == "any" ? "down" : s.slide)
    }
}
