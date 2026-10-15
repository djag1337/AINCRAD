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
        XCTAssertLessThanOrEqual(root.children?.count ?? 0, 9, "short enough that every row is clickable")
        XCTAssertEqual(root.children?.first { $0.name == "Mac Settings" }?.children?.count, MacSettings.sections.count)
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

final class WindowControlTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1050)

    func testHalvesThirdsQuarters() {
        let cur = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertEqual(WindowControl.frame(for: "left", in: screen, current: cur), CGRect(x: 0, y: 0, width: 960, height: 1050))
        XCTAssertEqual(WindowControl.frame(for: "right", in: screen, current: cur)?.minX, 960)
        XCTAssertEqual(WindowControl.frame(for: "top", in: screen, current: cur)?.minY, 525, "Cocoa: top half sits higher")
        XCTAssertEqual(WindowControl.frame(for: "third-center", in: screen, current: cur), CGRect(x: 640, y: 0, width: 640, height: 1050))
        XCTAssertEqual(WindowControl.frame(for: "two-thirds-right", in: screen, current: cur)?.width, 1280)
        XCTAssertEqual(WindowControl.frame(for: "bottom-right", in: screen, current: cur), CGRect(x: 960, y: 0, width: 960, height: 525))
        XCTAssertEqual(WindowControl.frame(for: "max", in: screen, current: cur), screen)
    }

    func testCenterKeepsSizeAndOffsetScreens() {
        let second = CGRect(x: 1920, y: 0, width: 1920, height: 1050)
        let c = WindowControl.frame(for: "center", in: second, current: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(c, CGRect(x: 1920 + 560, y: 225, width: 800, height: 600))
        XCTAssertEqual(WindowControl.frame(for: "left", in: second, current: .zero)?.minX, 1920)
        XCTAssertNil(WindowControl.frame(for: "next-display", in: screen, current: .zero), "handled separately")
    }

    func testEveryLayoutIsReachable() {
        let menu = WindowMenu.shared.children("windows:layouts")
        let count = menu.reduce(0) { $0 + ($1.children?.count ?? 0) }
        XCTAssertEqual(count, WindowControl.layouts.count)
        XCTAssertEqual(WindowMenu.commandResults("window left").first?.name, "Window: Left Half")
        XCTAssertTrue(WindowMenu.commandResults("safari").isEmpty)
    }
}
