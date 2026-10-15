import AppKit
import CoreAudio
import AudioToolbox
import CoreLocation
import CoreWLAN
import IOBluetooth
import IOKit.pwr_mgt

/// The system settings AINCRAD's System menu reads and changes, each through Apple's own
/// frameworks. Anything that needs a macOS permission asks only when that control is first used.
enum SystemControls {

    // MARK: Sound

    struct AudioDevice: Equatable {
        let id: AudioDeviceID
        let name: String
        let hasOutput: Bool
        let hasInput: Bool
    }

    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func channels(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func audioDevices() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var nameAddr = address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &name) == noErr, let n = name?.takeRetainedValue() else { return nil }
            return AudioDevice(id: id, name: n as String, hasOutput: channels(id, kAudioObjectPropertyScopeOutput) > 0,
                               hasInput: channels(id, kAudioObjectPropertyScopeInput) > 0)
        }
    }

    static func defaultDevice(output: Bool) -> AudioDeviceID {
        var addr = address(output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func setDefaultDevice(_ id: AudioDeviceID, output: Bool) {
        var addr = address(output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice)
        var value = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        if output {
            // Alert and UI sounds follow the main output, as they do in Control Center.
            var sys = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &sys, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        }
    }

    /// The default output's volume (0…1), or nil when that device has no volume control (HDMI, some interfaces).
    static func volume() -> Float? {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        let id = defaultDevice(output: true)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr else { return nil }
        return v
    }

    static func setVolume(_ value: Float) {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        var v = Float32(min(max(value, 0), 1))
        AudioObjectSetPropertyData(defaultDevice(output: true), &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        if v > 0, isMuted() { setMuted(false) }
    }

    static func isMuted() -> Bool {
        var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        let id = defaultDevice(output: true)
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var m: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &m)
        return m != 0
    }

    static func canMute() -> Bool {
        var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        return AudioObjectHasProperty(defaultDevice(output: true), &addr)
    }

    static func setMuted(_ on: Bool) {
        var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        var m: UInt32 = on ? 1 : 0
        AudioObjectSetPropertyData(defaultDevice(output: true), &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
    }

    // MARK: Wi-Fi

    static var wifi: CWInterface? { CWWiFiClient.shared().interface() }

    /// Network names need Location access on current macOS; without it scans return no names.
    static var locationStatus: CLAuthorizationStatus { CLLocationManager().authorizationStatus }
    private static let location = CLLocationManager()
    static func requestLocation() { location.requestWhenInUseAuthorization() }

    struct Network: Equatable {
        let ssid: String
        let bars: Int       // 1…3
        let secure: Bool
        let current: Bool
    }

    /// Scans (1–3 s); call off the main thread.
    static func scanNetworks() -> [Network] {
        guard let wifi, wifi.powerOn(), let found = try? wifi.scanForNetworks(withName: nil) else { return [] }
        let current = wifi.ssid()
        var best: [String: CWNetwork] = [:]
        for n in found {
            guard let ssid = n.ssid, !ssid.isEmpty else { continue }
            if let have = best[ssid], have.rssiValue >= n.rssiValue { continue }
            best[ssid] = n
        }
        return best.values.map { n in
            let rssi = n.rssiValue
            return Network(ssid: n.ssid ?? "", bars: rssi > -60 ? 3 : rssi > -72 ? 2 : 1,
                           secure: !n.supportsSecurity(.none), current: n.ssid == current)
        }.sorted { ($0.current ? 1 : 0, $0.bars) > ($1.current ? 1 : 0, $1.bars) }
    }

    /// Joins a network macOS already knows (its password is in the keychain). False if it needs one.
    static func join(_ ssid: String) -> Bool {
        guard let wifi, let found = try? wifi.scanForNetworks(withName: ssid), let network = found.max(by: { $0.rssiValue < $1.rssiValue }) else { return false }
        do { try wifi.associate(to: network, password: nil); return true } catch { return false }
    }

    // MARK: Bluetooth

    struct BluetoothDevice { let name: String; let connected: Bool; let address: String }

    /// Paired devices (asks for Bluetooth access the first time). Call off the main thread.
    static func bluetoothDevices() -> [BluetoothDevice] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return paired.map { BluetoothDevice(name: $0.name ?? $0.addressString ?? "Device", connected: $0.isConnected(), address: $0.addressString ?? "") }
            .sorted { ($0.connected ? 0 : 1, $0.name) < ($1.connected ? 0 : 1, $1.name) }
    }

    static func setBluetooth(_ address: String, connected: Bool) {
        guard let device = IOBluetoothDevice(addressString: address) else { return }
        _ = connected ? device.openConnection() : device.closeConnection()
    }

    // MARK: Appearance

    static var isDark: Bool { UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" }

    /// Through System Events (macOS asks once for permission to control it).
    static func setDark(_ on: Bool) {
        run("tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)")
    }

    // MARK: Power

    private static var awake: IOPMAssertionID = 0
    static var keepingAwake: Bool { awake != 0 }

    static func setKeepAwake(_ on: Bool) {
        if on, awake == 0 {
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn), "AINCRAD Keep Awake" as CFString, &id) == kIOReturnSuccess {
                awake = id
            }
        } else if !on, awake != 0 {
            IOPMAssertionRelease(awake)
            awake = 0
        }
        Log.info("system: keep awake \(on)")
    }

    static func sleep() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["sleepnow"]
        try? p.run()
    }

    /// Restart / shut down / log out through loginwindow's own confirmation dialog,
    /// so macOS asks "Are you sure?" and offers to reopen windows, as from the Apple menu.
    static func showPowerDialog(_ kind: String) {
        let event = ["restart": "rrst", "shutdown": "rsdn", "logout": "rlgo"][kind] ?? "rrst"
        run("tell application \"loginwindow\" to «event aevt\(event)»")
    }

    private static func run(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error { Log.error("system: script failed: \(error[NSAppleScript.errorMessage] ?? error)") }
        }
    }

    static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:" + pane) { NSWorkspace.shared.open(url) }
    }
}
