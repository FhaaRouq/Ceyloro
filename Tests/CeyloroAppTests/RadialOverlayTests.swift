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

    func testRadialOverlayViewAccessibilityElements() {
        let view = RadialOverlayView()
        view.mode = .convert
        view.items = [
            WheelItem(title: "JPG", target: .jpg, action: nil),
            WheelItem(title: "PNG", target: .png, action: nil)
        ]

        XCTAssertTrue(view.isAccessibilityElement())
        XCTAssertEqual(view.accessibilityRole(), .group)
        XCTAssertEqual(view.accessibilityLabel(), "Menu Radial Ceyloro - Konversi")

        let children = view.accessibilityChildren() as? [RadialSectorAccessibilityElement]
        XCTAssertEqual(children?.count, 2)
        XCTAssertEqual(children?.first?.accessibilityLabel(), "JPG")
        XCTAssertNil(children?.first?.accessibilityValue())

        view.activeIndex = 0
        XCTAssertEqual(children?.first?.accessibilityValue() as? String, "Terpilih")
    }
}
