import XCTest
@testable import AINCRAD

final class ProductivityTests: XCTestCase {
    private func center() -> ProductivityCenter {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AINCRAD-productivity-tests-\(UUID().uuidString)")
        return ProductivityCenter(directory: url)
    }

    func testCommandParserRecognizesTimerAndCapture() {
        let center = center()
        XCTAssertEqual(center.commandResults("timer 25").first?.action, .builtin("productivity:timer:25"))
        guard case .builtin(let capture)? = center.commandResults("capture remember the raid").first?.action else {
            return XCTFail("missing capture command")
        }
        XCTAssertTrue(capture.hasPrefix("productivity:captureText:"))
    }

    func testCaptureAppearsInInbox() {
        let center = center()
        center.capture("Aincrad floor plan")
        XCTAssertEqual(center.captureMenu().first?.name, "Aincrad floor plan")
    }

    func testSystemMenuExposesWindowAndLockActions() {
        let actions = center().systemMenu().compactMap(\.action)
        XCTAssertTrue(actions.contains(.builtin("productivity:window:left")))
        XCTAssertTrue(actions.contains(.builtin("productivity:lock")))
    }
}
