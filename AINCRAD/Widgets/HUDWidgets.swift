import AppKit
import CoreAudio
import CoreWLAN
import Darwin
import IOKit.ps
import IOKit.pwr_mgt

// MARK: Shared drawing

/// The anime's slanted bar: a track and a fill clipped to a parallelogram-ish shape.
private struct SlantBar {
    let track = CAShapeLayer(), holder = CALayer(), fill = CALayer()
    var width: CGFloat = 0

    mutating func build(in root: CALayer, frame: CGRect, line: NSColor) {
        width = frame.width
        let shape = CGMutablePath()
        shape.move(to: .zero)
        shape.addLine(to: CGPoint(x: frame.width, y: 0))
        shape.addLine(to: CGPoint(x: frame.width - frame.height * 0.6, y: frame.height))
        shape.addLine(to: CGPoint(x: 0, y: frame.height))
        shape.closeSubpath()
        track.frame = frame
        track.path = shape
        track.fillColor = NSColor.black.withAlphaComponent(0.25).cgColor
        track.strokeColor = line.withAlphaComponent(0.6).cgColor
        track.lineWidth = 1
        root.addSublayer(track)
        holder.frame = frame
        let mask = CAShapeLayer()
        mask.path = shape
        holder.mask = mask
        fill.anchorPoint = .zero
        fill.frame = CGRect(x: 0, y: 0, width: 0, height: frame.height)
        holder.addSublayer(fill)
        root.addSublayer(holder)
    }

    func set(_ fraction: Double, color: NSColor) {
        fill.bounds.size.width = width * CGFloat(min(max(fraction, 0), 1))
        fill.backgroundColor = color.cgColor
    }
}

private func hpColor(_ f: Double) -> NSColor { f > 0.5 ? HPBarContent.green : f > 0.2 ? HPBarContent.yellow : HPBarContent.red }

// MARK: Party (busiest apps)

/// CPU use per running app, from the kernel's task times (no permissions needed).
final class AppLoad {
    static let shared = AppLoad()
    struct Member { let name: String; let icon: NSImage?; let cpu: Double }

    private var last: [pid_t: UInt64] = [:]
    private var lastTime = DispatchTime.now().uptimeNanoseconds
    private let ticksToNs: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom)
    }()
    private let cores = Double(ProcessInfo.processInfo.activeProcessorCount)

    /// The `count` busiest regular apps since the previous call, CPU as a share of the whole machine (0…1).
    func top(_ count: Int) -> [Member] {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = Double(now - lastTime)
        lastTime = now
        var current: [pid_t: UInt64] = [:]
        var members: [Member] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let total = info.pti_total_user + info.pti_total_system
            current[pid] = total
            guard let before = last[pid], elapsed > 0 else { continue }
            let share = Double(total &- before) * ticksToNs / elapsed / cores
            members.append(Member(name: app.localizedName ?? "App", icon: app.icon, cpu: min(max(share, 0), 1)))
        }
        last = current
        return Array(members.sorted { $0.cpu > $1.cpu }.prefix(count))
    }
}

/// Your busiest apps as an SAO party: each member's HP is how much CPU it leaves free.
final class PartyContent: WidgetContent {
    private var timer: Timer?
    private var rows: [(icon: CALayer, name: CATextLayer, bar: SlantBar, readout: CATextLayer)] = []

    override func build() {
        let fs = config.style.fontSize
        let header = text("PARTY", size: fs * 0.75, color: accent)
        header.font = ThemeFonts.display(theme, fs * 0.75)
        header.frame = CGRect(x: 14, y: 10, width: size.width - 28, height: lineHeight(fs * 0.75) + 2)
        let count = max(1, min(Int(config.prop("count", "3")) ?? 3, 6))
        let top = header.frame.maxY + 8
        let rowH = (size.height - top - 8) / CGFloat(count)
        for i in 0..<count {
            let y = top + CGFloat(i) * rowH
            let icon = CALayer()
            let s = min(rowH - 8, 30)
            icon.frame = CGRect(x: 14, y: y + (rowH - s) / 2, width: s, height: s)
            icon.contentsGravity = .resizeAspect
            root.addSublayer(icon)
            let name = text("—", size: fs * 0.8)
            name.frame = CGRect(x: icon.frame.maxX + 8, y: y + 2, width: size.width * 0.45, height: lineHeight(fs * 0.8) + 2)
            let readout = text("", size: fs * 0.65, color: textColor.withAlphaComponent(0.75), align: .right)
            readout.frame = CGRect(x: size.width - 104, y: y + 4, width: 90, height: lineHeight(fs * 0.65) + 2)
            var bar = SlantBar()
            bar.build(in: root, frame: CGRect(x: icon.frame.maxX + 8, y: name.frame.maxY + 2, width: size.width - icon.frame.maxX - 22, height: 7), line: textColor)
            rows.append((icon, name, bar, readout))
        }
    }

    override func start() {
        _ = AppLoad.shared.top(0)   // prime the baseline
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }

    override func stop() { timer?.invalidate(); timer = nil }

    private func refresh() {
        let members = AppLoad.shared.top(rows.count)
        Motion.instant {
            for (i, row) in rows.enumerated() {
                guard i < members.count else {
                    row.name.string = "—"; row.readout.string = ""; row.icon.contents = nil; row.bar.set(0, color: .clear)
                    continue
                }
                let m = members[i], hp = 1 - m.cpu
                row.name.string = m.name
                row.icon.contents = m.icon?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                row.readout.string = "HP \(Int((hp * 100).rounded()))"
                row.bar.set(hp, color: hpColor(hp))
            }
        }
    }

    deinit { stop() }
}

// MARK: Status effects

/// Buffs and debuffs read from the system: Wi-Fi, battery, mute, keep-awake, load, disk, network.
enum StatusEffects {
    struct Effect { let symbol: String; let label: String; let good: Bool }

    static func current() -> [Effect] {
        var out: [Effect] = []
        if let wifi = CWWiFiClient.shared().interface() {
            if !wifi.powerOn() {
                out.append(Effect(symbol: "wifi.slash", label: "Wi-Fi off", good: false))
            } else {
                let rssi = wifi.rssiValue()
                if rssi == 0 { out.append(Effect(symbol: "wifi.exclamationmark", label: "No Wi-Fi", good: false)) }
                else if rssi > -60 { out.append(Effect(symbol: "wifi", label: "Strong signal", good: true)) }
                else { out.append(Effect(symbol: "wifi", label: "Weak signal", good: rssi > -75)) }
            }
        }
        if let b = DataHub.shared.sample(.battery), let f = b.fraction {
            out.append(f < 0.2 ? Effect(symbol: "battery.25percent", label: "Low battery", good: false)
                               : Effect(symbol: "battery.100percent.bolt", label: "\(Int(f * 100))%", good: true))
        }
        if outputMuted() { out.append(Effect(symbol: "speaker.slash.fill", label: "Muted", good: false)) }
        if keepAwake() { out.append(Effect(symbol: "cup.and.saucer.fill", label: "Awake", good: true)) }
        if let cpu = DataHub.shared.sample(.cpu)?.fraction, cpu > 0.8 {
            out.append(Effect(symbol: "flame.fill", label: "High load", good: false))
        }
        if let disk = DataHub.shared.sample(.disk)?.fraction, disk > 0.9 {
            out.append(Effect(symbol: "externaldrive.fill.badge.exclamationmark", label: "Disk full", good: false))
        }
        if out.isEmpty { out.append(Effect(symbol: "sparkles", label: "All clear", good: true)) }
        return out
    }

    private static func outputMuted() -> Bool {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr else { return false }
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                          mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted) == noErr else { return false }
        return muted != 0
    }

    /// Something is holding off idle sleep (a video playing, caffeinate, a download…).
    private static func keepAwake() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess, let dict = status?.takeRetainedValue() as? [String: Int] else { return false }
        return (dict[kIOPMAssertionTypePreventUserIdleSystemSleep as String] ?? 0) > 0
            || (dict[kIOPMAssertionTypePreventUserIdleDisplaySleep as String] ?? 0) > 0
    }
}

/// A row of SAO status-effect icons: buffs in the accent colour, debuffs in red.
final class StatusContent: WidgetContent {
    private var timer: Timer?
    private var tokens: [DataHub.Token] = []
    private var dynamic: [CALayer] = []

    override func build() {
        let fs = config.style.fontSize
        let header = text("STATUS", size: fs * 0.75, color: accent)
        header.font = ThemeFonts.display(theme, fs * 0.75)
        header.frame = CGRect(x: 14, y: 10, width: size.width - 28, height: lineHeight(fs * 0.75) + 2)
    }

    override func start() {
        // Keep the readings this widget looks at fresh.
        tokens = [StatSource.cpu, .disk, .battery].map { DataHub.shared.subscribe(key: $0.rawValue) { _ in } }
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.render() }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.render() }
    }

    override func stop() {
        timer?.invalidate(); timer = nil
        tokens.forEach(DataHub.shared.unsubscribe); tokens = []
    }

    private func render() {
        let effects = StatusEffects.current()
        let fs = config.style.fontSize
        Motion.instant {
            dynamic.forEach { $0.removeFromSuperlayer() }
            dynamic = []
            let top = 10 + lineHeight(fs * 0.75) + 10
            let tile: CGFloat = min(44, size.height - top - lineHeight(fs * 0.6) - 12)
            var x: CGFloat = 14
            for e in effects {
                guard x + tile <= size.width - 10 else { break }
                let color = e.good ? accent : HPBarContent.red
                let box = CALayer()
                box.frame = CGRect(x: x, y: top, width: tile, height: tile)
                box.cornerRadius = 6
                box.backgroundColor = color.withAlphaComponent(0.16).cgColor
                box.borderColor = color.cgColor
                box.borderWidth = 1.5
                let icon = CALayer()
                icon.frame = box.bounds.insetBy(dx: tile * 0.2, dy: tile * 0.2)
                icon.contents = IconCache.shared.image("sf:" + e.symbol, size: icon.bounds.width, tint: color, scale: scale)
                icon.contentsGravity = .resizeAspect
                box.addSublayer(icon)
                root.addSublayer(box)
                let label = text(e.label, size: fs * 0.55, color: textColor.withAlphaComponent(0.8), align: .center)
                label.frame = CGRect(x: x - 10, y: top + tile + 4, width: tile + 20, height: lineHeight(fs * 0.55) + 2)
                dynamic += [box, label]
                x += tile + 22
            }
        }
    }

    deinit { stop() }
}

// MARK: Battle log

/// A running feed of what happened: apps opening and closing, launcher choices, messages.
final class BattleLog {
    static let shared = BattleLog()
    struct Entry { let time: Date; let text: String; let symbol: String }

    private(set) var entries: [Entry] = []
    private var listeners: [UUID: () -> Void] = [:]
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
                guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.activationPolicy == .regular else { return }
                self?.add("\(app.localizedName ?? "An app") joined", symbol: "plus.circle.fill")
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
                guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.activationPolicy == .regular else { return }
                self?.add("\(app.localizedName ?? "An app") left", symbol: "minus.circle.fill")
            },
        ]
    }

    func add(_ text: String, symbol: String = "bolt.fill") {
        entries.insert(Entry(time: Date(), text: text, symbol: symbol), at: 0)
        if entries.count > 50 { entries.removeLast(entries.count - 50) }
        listeners.values.forEach { $0() }
    }

    func listen(_ change: @escaping () -> Void) -> UUID {
        let id = UUID()
        listeners[id] = change
        return id
    }

    func unlisten(_ id: UUID) { listeners[id] = nil }
}

final class BattleLogContent: WidgetContent {
    private var listener: UUID?
    private var dynamic: [CALayer] = []

    override func build() {
        let fs = config.style.fontSize
        let header = text("BATTLE LOG", size: fs * 0.75, color: accent)
        header.font = ThemeFonts.display(theme, fs * 0.75)
        header.frame = CGRect(x: 14, y: 10, width: size.width - 28, height: lineHeight(fs * 0.75) + 2)
    }

    override func start() {
        listener = BattleLog.shared.listen { [weak self] in self?.render() }
        render()
    }

    override func stop() {
        if let listener { BattleLog.shared.unlisten(listener) }
        listener = nil
    }

    private func render() {
        let fs = config.style.fontSize * 0.7
        Motion.instant {
            dynamic.forEach { $0.removeFromSuperlayer() }
            dynamic = []
            var y = 10 + lineHeight(config.style.fontSize * 0.75) + 10
            let rowH = lineHeight(fs) + 6
            let entries = BattleLog.shared.entries
            if entries.isEmpty {
                let t = text("Quiet so far.", size: fs, color: textColor.withAlphaComponent(0.6))
                t.frame = CGRect(x: 14, y: y, width: size.width - 28, height: rowH)
                dynamic.append(t)
                return
            }
            for (i, e) in entries.enumerated() {
                guard y + rowH <= size.height - 6 else { break }
                let fade = max(0.35, 1 - CGFloat(i) * 0.12)
                let icon = CALayer()
                let s = lineHeight(fs) - 4
                icon.frame = CGRect(x: 14, y: y + 3, width: s, height: s)
                icon.contents = IconCache.shared.image("sf:" + e.symbol, size: s, tint: accent, scale: scale)
                icon.opacity = Float(fade)
                root.addSublayer(icon)
                let time = text(e.time.formatted(date: .omitted, time: .shortened), size: fs * 0.85,
                                color: textColor.withAlphaComponent(0.55 * fade), align: .right)
                time.frame = CGRect(x: size.width - 84, y: y + 1, width: 70, height: rowH)
                let line = text(e.text, size: fs, color: textColor.withAlphaComponent(fade))
                line.frame = CGRect(x: 14 + s + 8, y: y, width: size.width - s - 22 - 90, height: rowH)
                dynamic += [icon, time, line]
                y += rowH
            }
        }
    }

    deinit { stop() }
}

// MARK: EXP

/// Experience points that persist between launches: earned by choosing things in the launcher
/// and by active minutes at the Mac. Levels get steadily longer, like an RPG's.
final class ExpStore {
    static let shared = ExpStore()
    private(set) var exp = 0
    private var listeners: [UUID: (_ leveledUp: Bool) -> Void] = [:]
    private var timer: Timer?
    private var saveWork: DispatchWorkItem?
    private var url: URL { ConfigStore.baseDirectory.appendingPathComponent("exp.json") }

    /// Total EXP needed to reach `level` (level 1 needs 0).
    static func threshold(_ level: Int) -> Int { 50 * (level - 1) * level }
    static func level(for exp: Int) -> Int {
        var l = 1
        while threshold(l + 1) <= exp { l += 1 }
        return l
    }
    var level: Int { ExpStore.level(for: exp) }

    func start() {
        guard timer == nil else { return }
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([String: Int].self, from: data) {
            exp = saved["exp"] ?? 0
        }
        // One EXP per minute you're actually at the Mac (any input in the last minute).
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
            if idle < 60 { self?.gain(1) }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func gain(_ amount: Int, reason: String? = nil) {
        let before = level
        exp += amount
        let up = level > before
        if up { BattleLog.shared.add("Level up! LV \(level)", symbol: "star.fill") }
        listeners.values.forEach { $0(up) }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            try? JSONEncoder().encode(["exp": self.exp]).write(to: self.url, options: .atomic)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func listen(_ change: @escaping (Bool) -> Void) -> UUID {
        let id = UUID()
        listeners[id] = change
        return id
    }

    func unlisten(_ id: UUID) { listeners[id] = nil }
}

/// Level and EXP bar, with a level-up flash.
final class ExpContent: WidgetContent {
    private var listener: UUID?
    private var levelText: CATextLayer!
    private var expText: CATextLayer!
    private var bar = SlantBar()
    private let flash = CATextLayer()

    override func build() {
        let fs = config.style.fontSize
        levelText = text("LV 1", size: fs * 1.3)
        levelText.font = ThemeFonts.display(theme, fs * 1.3)
        levelText.frame = CGRect(x: 14, y: 8, width: size.width * 0.5, height: lineHeight(fs * 1.3) + 2)
        expText = text("", size: fs * 0.7, color: textColor.withAlphaComponent(0.75), align: .right)
        expText.frame = CGRect(x: size.width * 0.4, y: 14, width: size.width * 0.6 - 14, height: lineHeight(fs * 0.7) + 2)
        bar.build(in: root, frame: CGRect(x: 14, y: levelText.frame.maxY + 6, width: size.width - 28, height: 10), line: textColor)
        let f = ThemeFonts.display(theme, fs * 1.1)
        flash.font = f
        flash.fontSize = f.pointSize
        flash.string = "LEVEL UP!"
        flash.alignmentMode = .center
        flash.foregroundColor = accent.cgColor
        flash.contentsScale = scale
        flash.frame = CGRect(x: 0, y: (size.height - lineHeight(fs * 1.1)) / 2, width: size.width, height: lineHeight(fs * 1.1) + 2)
        flash.shadowColor = accent.cgColor
        flash.shadowOpacity = 1
        flash.shadowRadius = 8
        flash.shadowOffset = .zero
        flash.opacity = 0
        root.addSublayer(flash)
        render(leveledUp: false)
    }

    override func start() { listener = ExpStore.shared.listen { [weak self] up in self?.render(leveledUp: up) } }
    override func stop() { if let listener { ExpStore.shared.unlisten(listener) }; listener = nil }

    private func render(leveledUp: Bool) {
        let store = ExpStore.shared, lv = store.level
        let from = ExpStore.threshold(lv), to = ExpStore.threshold(lv + 1)
        let fraction = Double(store.exp - from) / Double(max(to - from, 1))
        Motion.instant {
            levelText.string = "LV \(lv)"
            expText.string = "\(store.exp - from) / \(to - from) EXP"
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        bar.set(fraction, color: accent)
        CATransaction.commit()
        guard leveledUp else { return }
        let pop = CAKeyframeAnimation(keyPath: "opacity")
        pop.values = [0, 1, 1, 0]
        pop.keyTimes = [0, 0.15, 0.75, 1]
        pop.duration = 1.8
        flash.add(pop, forKey: "levelup")
        let glow = CABasicAnimation(keyPath: "shadowOpacity")
        glow.fromValue = 1
        glow.toValue = Float(theme.effects.shadowOpacity)
        glow.duration = 1.2
        root.add(glow, forKey: "glow")
    }

    deinit { stop() }
}
