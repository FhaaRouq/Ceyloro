import XCTest
@testable import Ceyloro

final class HotKeyMonitorTests: XCTestCase {
    func testFinderSelectionResultEquality() {
        XCTAssertEqual(FinderSelectionResult.noSelection, FinderSelectionResult.noSelection)
        XCTAssertEqual(FinderSelectionResult.permissionDenied(reason: "A"), FinderSelectionResult.permissionDenied(reason: "A"))
        XCTAssertNotEqual(FinderSelectionResult.permissionDenied(reason: "A"), FinderSelectionResult.permissionDenied(reason: "B"))
        XCTAssertEqual(FinderSelectionResult.scriptError("err"), FinderSelectionResult.scriptError("err"))
        let u1 = URL(fileURLWithPath: "/tmp/a.png")
        XCTAssertEqual(FinderSelectionResult.success([u1]), FinderSelectionResult.success([u1]))
    }

    func testAccessibilityStatusCanBeQueried() {
        // HotKeyMonitor.isAccessibilityGranted should return a boolean without crashing
        _ = HotKeyMonitor.isAccessibilityGranted
    }

    func testLogSanitizationReplacesHomeDirectory() {
        let home = "/Users/testuser"
        let rawMessage = "Job submitted for /Users/testuser/Documents/secret.png"
        let sanitized = AppDelegate.sanitizeLogMessage(rawMessage, homeDirectory: home)
        XCTAssertEqual(sanitized, "Job submitted for ~/Documents/secret.png")
    }
}
