import Carbon.HIToolbox

/// Carbon global hotkey: works without Accessibility or Input Monitoring permission.
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?
    private let id: UInt32

    init?(_ spec: HotKeySpec, handler: @escaping () -> Void) {
        guard let code = HotKey.keyCodes[spec.key.lowercased()] else { return nil }
        let mods = spec.modifiers.reduce(UInt32(0)) { $0 | (HotKey.modifierMasks[$1.lowercased()] ?? 0) }
        HotKey.installHandlerIfNeeded()
        id = HotKey.nextID
        HotKey.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x41494E43), id: id) // 'AINC'
        guard RegisterEventHotKey(UInt32(code), mods, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
        HotKey.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }

    /// "option+shift+1" → HotKeySpec; nil when the key or a modifier isn't recognised.
    static func parse(_ text: String) -> HotKeySpec? {
        var parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.popLast(), keyCodes[key] != nil, !parts.isEmpty || (key.count > 1 && key.hasPrefix("f")),
              parts.allSatisfy({ modifierMasks[$0] != nil }) else { return nil }
        return HotKeySpec(key: key, modifiers: parts)
    }

    static func string(_ spec: HotKeySpec) -> String { (spec.modifiers + [spec.key]).joined(separator: "+") }

    static func keyName(forKeyCode code: Int) -> String? {
        keyCodes.first { $0.value == code && $0.key.count <= 6 && $0.key != "ctrl" }?.key
    }

    static func display(_ spec: HotKeySpec) -> String {
        let order: [(String, String)] = [("control", "⌃"), ("option", "⌥"), ("shift", "⇧"), ("command", "⌘")]
        let mods = order.filter { m in spec.modifiers.contains { $0.lowercased() == m.0 } }.map(\.1).joined()
        return mods + (spec.key.count == 1 ? spec.key.uppercased() : spec.key.capitalized)
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            HotKey.handlers[hk.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }

    static let modifierMasks: [String: UInt32] = [
        "control": UInt32(controlKey), "ctrl": UInt32(controlKey),
        "option": UInt32(optionKey), "alt": UInt32(optionKey),
        "shift": UInt32(shiftKey),
        "command": UInt32(cmdKey), "cmd": UInt32(cmdKey),
    ]

    static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape, "`": kVK_ANSI_Grave,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]
}
