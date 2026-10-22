import XCTest
import AppKit
@testable import Ceyloro
@testable import CeyloroCore

final class AppDelegateWheelItemTests: XCTestCase {
    func testActionWheelItems() {
        let appDelegate = AppDelegate()
        let items = appDelegate.wheelItems(for: [URL(fileURLWithPath: "/tmp/test.png")], mode: .actions)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.map(\.title), ["Salin", "Salin Jalur", "Terminal", "AirDrop"])
        XCTAssertEqual(items[0].action, .copy)
        XCTAssertEqual(items[1].action, .copyPath)
        XCTAssertEqual(items[2].action, .terminal)
        XCTAssertEqual(items[3].action, .airDrop)
    }

    func testToolsWheelItemsOffersCompressionForImage() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let imageURL = tempDir.appendingPathComponent("photo.jpg")
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
        image.unlockFocus()
        try XCTUnwrap(image.tiffRepresentation).write(to: imageURL)
        let appDelegate = AppDelegate()
        let items = appDelegate.wheelItems(for: [imageURL], mode: .tools)
        XCTAssertEqual(items.map(\.title), ["Kompres"])
        XCTAssertEqual(items.first?.action, .compress)
    }

    func testSubtitleWheelItems() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let srtFile = tempDir.appendingPathComponent("movie.srt")
        let srtContent = "1\n00:00:01,000 --> 00:00:04,000\nHello World\n"
        try Data(srtContent.utf8).write(to: srtFile)

        let appDelegate = AppDelegate()
        let items = appDelegate.wheelItems(for: [srtFile], mode: .convert)
        let targets = items.compactMap(\.target?.fileExtension)
        XCTAssertTrue(targets.contains("vtt"))
        XCTAssertTrue(targets.contains("txt"))
        XCTAssertFalse(targets.contains("srt"))
    }

    func testImageWheelItems() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let pngFile = tempDir.appendingPathComponent("photo.png")
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Could not create PNG")
            return
        }
        try pngData.write(to: pngFile)

        let appDelegate = AppDelegate()
        let items = appDelegate.wheelItems(for: [pngFile], mode: .convert)
        let targets = items.compactMap(\.target?.fileExtension)
        XCTAssertTrue(targets.contains("jpg"))
        XCTAssertTrue(targets.contains("pdf"))
        XCTAssertFalse(targets.contains("png"))
    }
}
