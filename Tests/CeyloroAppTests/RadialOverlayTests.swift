import AppKit
import XCTest
@testable import Ceyloro

final class RadialOverlayTests: XCTestCase {
    func testCombinedScreenFrameSingleScreen() {
        let screens = [NSRect(x: 0, y: 0, width: 1440, height: 900)]
        let frame = RadialOverlay.combinedScreenFrame(screens: screens)
        XCTAssertEqual(frame, NSRect(x: 0, y: 0, width: 1440, height: 900))
    }

    func testCombinedScreenFrameMultipleScreensPositiveOffset() {
        let screen1 = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let screen2 = NSRect(x: 1920, y: 0, width: 2560, height: 1440)
        let frame = RadialOverlay.combinedScreenFrame(screens: [screen1, screen2])
        XCTAssertEqual(frame, NSRect(x: 0, y: 0, width: 4480, height: 1440))
    }

    func testCombinedScreenFrameMultipleScreensNegativeOffset() {
        // External monitor placed to the left of the main display
        let leftScreen = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let mainScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = RadialOverlay.combinedScreenFrame(screens: [mainScreen, leftScreen])
        XCTAssertEqual(frame, NSRect(x: -1920, y: 0, width: 3360, height: 1080))
    }

    func testCombinedScreenFrameEmptyFallback() {
        let fallback = NSRect(x: 10, y: 20, width: 800, height: 600)
        let frame = RadialOverlay.combinedScreenFrame(screens: [], fallback: fallback)
        XCTAssertEqual(frame, fallback)
    }
}
