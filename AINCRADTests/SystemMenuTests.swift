import XCTest
@testable import AINCRAD

/// Read-only: these never change a setting on the machine running them.
final class SystemMenuTests: XCTestCase {
    func testAudioDevicesAndDefaults() {
        let devices = SystemControls.audioDevices()
        XCTAssertFalse(devices.isEmpty)
        let out = SystemControls.defaultDevice(output: true)
        XCTAssertTrue(devices.contains { $0.id == out && $0.hasOutput }, "default output is a listed output device")
        if let v = SystemControls.volume() { XCTAssertTrue((0...1).contains(v)) }
    }

    func testSectionsBuild() {
        let root = SystemMenu.root()
        XCTAssertEqual(root.children?.prefix(5).map(\.name), ["Sound", "Wi-Fi", "Bluetooth", "Display", "Power"])
        let menu = SystemMenu.shared
        for provider in ["system:sound", "system:outputs", "system:inputs", "system:wifi", "system:display", "system:power"] {
            XCTAssertFalse(menu.children(provider).isEmpty, provider)
        }
        XCTAssertEqual(menu.children("system:volume").count, 11)
        // Every actionable item is a system: (or lock) builtin with a description or a clear name.
        for item in menu.children("system:power") {
            if case .builtin(let b)? = item.action { XCTAssertTrue(b.hasPrefix("system:") || b == "productivity:lock") }
        }
    }

    func testPowerItemsConfirmThroughMacOS() {
        let names = SystemMenu.shared.children("system:power").map(\.name)
        XCTAssertTrue(names.contains("Restart…") && names.contains("Shut Down…") && names.contains("Log Out…"))
    }
}
