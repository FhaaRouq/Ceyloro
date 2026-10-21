import AppKit
import XCTest
@testable import Ceyloro

final class DragMonitorTests: XCTestCase {
    func testStartAndStopLifecycleIsIdempotent() {
        let monitor = DragMonitor()
        // Calling stop before start should not crash
        monitor.stop()

        // Calling start should initialize timers and monitors
        monitor.start()
        // Calling start again should be a no-op
        monitor.start()

        // Calling stop should clean up
        monitor.stop()
        // Multiple stop calls should be safe
        monitor.stop()
    }

    func testDiagnosticCallbackCanBeSetAndInvoked() {
        let monitor = DragMonitor()
        var receivedDiagnostic: String?
        monitor.onDiagnostic = { message in
            receivedDiagnostic = message
        }

        monitor.onDiagnostic?("Test message")
        XCTAssertEqual(receivedDiagnostic, "Test message")
    }

    func testWheelChangeCallbackReceivesArguments() {
        let monitor = DragMonitor()
        var capturedURLs: [URL]?
        var capturedPoint: NSPoint?
        var capturedFlags: NSEvent.ModifierFlags?

        monitor.onWheelChange = { urls, point, flags in
            capturedURLs = urls
            capturedPoint = point
            capturedFlags = flags
        }

        let testURL = URL(fileURLWithPath: "/tmp/sample.png")
        let testPoint = NSPoint(x: 100, y: 200)
        let testFlags: NSEvent.ModifierFlags = [.shift, .control]

        monitor.onWheelChange?([testURL], testPoint, testFlags)

        XCTAssertEqual(capturedURLs, [testURL])
        XCTAssertEqual(capturedPoint, testPoint)
        XCTAssertEqual(capturedFlags, testFlags)
    }

    func testDragEndCallbackFires() {
        let monitor = DragMonitor()
        var dragEnded = false
        monitor.onDragEnd = {
            dragEnded = true
        }

        monitor.onDragEnd?()
        XCTAssertTrue(dragEnded)
    }

    func testPasteboardFileReadingCompatibility() {
        let pasteboard = NSPasteboard(name: .drag)
        let tempURL = URL(fileURLWithPath: "/tmp/ceyloro-drag-test.jpg")
        pasteboard.clearContents()
        pasteboard.writeObjects([tempURL as NSURL])

        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        let urls = objects.compactMap { $0 as URL }
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.path, tempURL.path)
    }
}
