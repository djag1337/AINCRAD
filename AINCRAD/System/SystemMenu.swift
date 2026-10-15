import AppKit
import CoreLocation

/// The launcher's System circle: a Control Center replacement in SAO menus. Items are built when
/// a column opens (`children`), and run as "system:" builtins (`perform`). Slow reads — Wi-Fi
/// scans, Bluetooth devices — happen off the main thread and refresh the open column when done.
final class SystemMenu {
    static let shared = SystemMenu()
    /// A provider's data arrived; the launcher refreshes that column if it's open.
    var onUpdate: ((String) -> Void)?

    private var networks: (time: Date, list: [SystemControls.Network])?
    private var scanning = false
    private var bluetooth: (time: Date, list: [SystemControls.BluetoothDevice])?
    private var loadingBluetooth = false

    static func root() -> MenuItem {
        var kids = [
            MenuItem(id: "system:sound", name: "Sound", icon: "sf:speaker.wave.2.fill", provider: "system:sound"),
            MenuItem(id: "system:wifi", name: "Wi-Fi", icon: "sf:wifi", provider: "system:wifi"),
            MenuItem(id: "system:bluetooth", name: "Bluetooth", icon: "sf:dot.radiowaves.left.and.right", provider: "system:bluetooth"),
            MenuItem(id: "system:display", name: "Display", icon: "sf:display", provider: "system:display"),
            MenuItem(id: "system:power", name: "Power", icon: "sf:power", provider: "system:power"),
        ]
        if DataHub.shared.sample(.battery)?.fraction != nil {
            kids.append(MenuItem(id: "system:battery", name: "Battery", icon: "sf:battery.75percent", provider: "system:battery"))
        }
        return MenuItem(id: "aincrad:system", name: "System", icon: "sf:switch.2", children: kids,
                        description: "Sound, Wi-Fi, Bluetooth, display and power, without opening Control Center.")
    }

    private func item(_ name: String, _ icon: String, _ command: String? = nil, _ about: String? = nil) -> MenuItem {
        MenuItem(id: "system-item:" + name, name: name, icon: icon, action: command.map { .builtin("system:" + $0) }, description: about)
    }

    private func settings(_ name: String, _ pane: String) -> MenuItem {
        item(name, "sf:gearshape", "settings:" + pane, "Opens System Settings.")
    }

    // MARK: Building

    func children(_ provider: String) -> [MenuItem] {
        switch provider {
        case "system:sound": return sound()
        case "system:volume": return volumeSteps()
        case "system:outputs": return devices(output: true)
        case "system:inputs": return devices(output: false)
        case "system:wifi": return wifi()
        case "system:networks": return networkList()
        case "system:bluetooth": return bluetoothList()
        case "system:display": return display()
        case "system:power": return power()
        case "system:battery": return battery()
        default: return []
        }
    }

    private func sound() -> [MenuItem] {
        var out: [MenuItem] = []
        let devices = SystemControls.audioDevices()
        let output = devices.first { $0.id == SystemControls.defaultDevice(output: true) }
        if let v = SystemControls.volume() {
            out.append(MenuItem(id: "system-item:volume", name: "Volume: \(Int((v * 100).rounded()))%", icon: "sf:speaker.wave.3.fill",
                                provider: "system:volume", description: "Set the volume of \(output?.name ?? "the current output")."))
        } else {
            out.append(MenuItem(id: "system-item:novolume", name: "No volume control", icon: "sf:speaker.slash",
                                description: "\(output?.name ?? "This output") sets its own volume (common for HDMI and DisplayPort)."))
        }
        if SystemControls.canMute() {
            out.append(SystemControls.isMuted() ? item("Unmute", "sf:speaker.wave.2.fill", "mute:0") : item("Mute", "sf:speaker.slash.fill", "mute:1"))
        }
        out.append(MenuItem(id: "system-item:outputs", name: "Output: \(output?.name ?? "—")", icon: "sf:hifispeaker.fill", provider: "system:outputs"))
        let input = devices.first { $0.id == SystemControls.defaultDevice(output: false) }
        out.append(MenuItem(id: "system-item:inputs", name: "Input: \(input?.name ?? "—")", icon: "sf:mic.fill", provider: "system:inputs"))
        out.append(settings("Sound Settings…", "com.apple.Sound-Settings.extension"))
        return out
    }

    private func volumeSteps() -> [MenuItem] {
        let current = Int(((SystemControls.volume() ?? 0) * 10).rounded()) * 10
        return stride(from: 100, through: 0, by: -10).map { p in
            item("\(p)%", p == current ? "sf:checkmark.circle.fill" : (p == 0 ? "sf:speaker.fill" : "sf:speaker.wave.\(p < 40 ? 1 : p < 70 ? 2 : 3).fill"),
                 "volume:\(p)", "Set the volume to \(p)%.")
        }
    }

    private func devices(output: Bool) -> [MenuItem] {
        let current = SystemControls.defaultDevice(output: output)
        let list = SystemControls.audioDevices().filter { output ? $0.hasOutput : $0.hasInput }
        if list.isEmpty { return [item("No devices", "sf:speaker.slash")] }
        return list.map { d in
            item(d.name, d.id == current ? "sf:checkmark.circle.fill" : (output ? "sf:speaker.wave.2" : "sf:mic"),
                 "\(output ? "output" : "input"):\(d.id)", "Use \(d.name) for sound \(output ? "output" : "input").")
        }
    }

    private func wifi() -> [MenuItem] {
        guard let wifi = SystemControls.wifi else { return [item("No Wi-Fi hardware", "sf:wifi.slash")] }
        guard wifi.powerOn() else {
            return [item("Turn Wi-Fi On", "sf:wifi", "wifi:1"), settings("Wi-Fi Settings…", "com.apple.wifi-settings-extension")]
        }
        var out = [item("Turn Wi-Fi Off", "sf:wifi.slash", "wifi:0", "Disconnects from Wi-Fi.")]
        if let ssid = wifi.ssid() {
            out.append(item("Connected: \(ssid)", "sf:checkmark.circle.fill", nil, "Signal \(wifi.rssiValue()) dBm."))
        }
        out.append(MenuItem(id: "system-item:networks", name: "Networks", icon: "sf:list.bullet", provider: "system:networks"))
        out.append(settings("Wi-Fi Settings…", "com.apple.wifi-settings-extension"))
        return out
    }

    private func networkList() -> [MenuItem] {
        switch SystemControls.locationStatus {
        case .notDetermined:
            return [item("Show network names…", "sf:location.fill", "location",
                         "macOS only reveals Wi-Fi names to apps with Location access. It asks once.")]
        case .denied, .restricted:
            return [item("Network names need Location access", "sf:location.slash", "settings:com.apple.preference.security?Privacy_LocationServices",
                         "Allow AINCRAD under Privacy & Security › Location Services.")]
        default: break
        }
        if let cached = networks, Date().timeIntervalSince(cached.time) < 30 {
            if cached.list.isEmpty { return [item("No networks found", "sf:wifi.exclamationmark")] }
            return cached.list.map { n in
                item(n.ssid + (n.secure ? "  🔒" : ""), n.current ? "sf:checkmark.circle.fill" : "sf:wifi",
                     n.current ? nil : "join:" + (n.ssid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? n.ssid),
                     n.current ? "Connected." : "Join \(n.ssid). Networks you've joined before connect straight away.")
            }
        }
        startScan()
        return [item("Scanning…", "sf:antenna.radiowaves.left.and.right")]
    }

    private func startScan() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let list = SystemControls.scanNetworks()
            DispatchQueue.main.async {
                self?.scanning = false
                self?.networks = (Date(), list)
                Log.info("system: wifi scan found \(list.count) networks")
                self?.onUpdate?("system:networks")
            }
        }
    }

    private func bluetoothList() -> [MenuItem] {
        var out: [MenuItem]
        if let cached = bluetooth, Date().timeIntervalSince(cached.time) < 15 {
            out = cached.list.map { d in
                item(d.name, d.connected ? "sf:checkmark.circle.fill" : "sf:circle",
                     "bt:\(d.address):\(d.connected ? 0 : 1)", d.connected ? "Connected. Choose to disconnect." : "Choose to connect.")
            }
            if out.isEmpty { out = [item("No paired devices", "sf:dot.radiowaves.left.and.right")] }
        } else {
            loadBluetooth()
            out = [item("Looking for devices…", "sf:dot.radiowaves.left.and.right")]
        }
        return out + [settings("Bluetooth Settings…", "com.apple.BluetoothSettings")]
    }

    private func loadBluetooth() {
        guard !loadingBluetooth else { return }
        loadingBluetooth = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let list = SystemControls.bluetoothDevices()
            DispatchQueue.main.async {
                self?.loadingBluetooth = false
                self?.bluetooth = (Date(), list)
                self?.onUpdate?("system:bluetooth")
            }
        }
    }

    private func display() -> [MenuItem] {
        [SystemControls.isDark ? item("Switch to Light Appearance", "sf:sun.max.fill", "dark:0")
                               : item("Switch to Dark Appearance", "sf:moon.fill", "dark:1"),
         settings("Displays Settings…", "com.apple.Displays-Settings.extension"),
         settings("Wallpaper Settings…", "com.apple.Wallpaper-Settings.extension")]
    }

    private func power() -> [MenuItem] {
        [SystemControls.keepingAwake ? item("Stop Keeping Awake", "sf:cup.and.saucer", "awake:0", "Let the display sleep normally again.")
                                     : item("Keep Awake", "sf:cup.and.saucer.fill", "awake:1", "Keeps the display from sleeping until you turn it off or quit AINCRAD."),
         MenuItem(id: "system-item:lock", name: "Lock Screen", icon: "sf:lock.fill", action: .builtin("productivity:lock")),
         item("Sleep", "sf:moon.zzz.fill", "sleep"),
         item("Log Out…", "sf:rectangle.portrait.and.arrow.right", "power:logout", "macOS asks to confirm."),
         item("Restart…", "sf:arrow.clockwise", "power:restart", "macOS asks to confirm."),
         item("Shut Down…", "sf:power", "power:shutdown", "macOS asks to confirm.")]
    }

    private func battery() -> [MenuItem] {
        let b = DataHub.shared.sample(.battery)
        return [item("Battery: \(b?.text ?? "—")", "sf:battery.75percent"), settings("Battery Settings…", "com.apple.Battery-Settings.extension")]
    }

    // MARK: Actions

    /// Runs "system:<command>:<argument>" builtins.
    func perform(_ builtin: String) {
        let parts = builtin.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return }
        let arg = parts.count > 2 ? parts[2] : ""
        Log.info("system: \(parts[1]) \(arg)")
        switch parts[1] {
        case "volume": SystemControls.setVolume((Float(arg) ?? 50) / 100)
        case "mute": SystemControls.setMuted(arg == "1")
        case "output": if let id = UInt32(arg) { SystemControls.setDefaultDevice(id, output: true) }
        case "input": if let id = UInt32(arg) { SystemControls.setDefaultDevice(id, output: false) }
        case "wifi": try? SystemControls.wifi?.setPower(arg == "1"); networks = nil
        case "location": SystemControls.requestLocation()
        case "join":
            let ssid = arg.removingPercentEncoding ?? arg
            DispatchQueue.global(qos: .userInitiated).async {
                if !SystemControls.join(ssid) {
                    DispatchQueue.main.async { SystemControls.openSettings("com.apple.wifi-settings-extension") }
                }
            }
        case "bt":
            let bits = arg.split(separator: ":").map(String.init)   // address has no ':' in IOBluetooth's dash form
            if bits.count == 2 {
                DispatchQueue.global(qos: .userInitiated).async { SystemControls.setBluetooth(bits[0], connected: bits[1] == "1") }
                bluetooth = nil
            }
        case "dark": SystemControls.setDark(arg == "1")
        case "awake": SystemControls.setKeepAwake(arg == "1")
        case "sleep": SystemControls.sleep()
        case "power": SystemControls.showPowerDialog(arg)
        case "settings": SystemControls.openSettings(arg)
        default: Log.error("system: unknown command \(parts[1])")
        }
    }
}
