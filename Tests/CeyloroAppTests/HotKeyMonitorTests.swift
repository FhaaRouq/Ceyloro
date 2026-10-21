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
}
