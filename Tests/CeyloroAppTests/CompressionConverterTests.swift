import XCTest
import AppKit
@testable import Ceyloro
@testable import CeyloroCore

final class CompressionConverterTests: XCTestCase {
    func testImageCompressionWritesASeparateJPG() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroCompression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("photo.jpg")
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.systemBlue.drawSwatch(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        try XCTUnwrap(representation.representation(using: .jpeg, properties: [.compressionFactor: 0.9])).write(to: input)

        let result = try CompressionConverter().compress(input: input, temporaryDirectory: root.appendingPathComponent("temp"), ffmpegURL: nil, encoders: [], preset: .balanced, progress: { _ in }, isCancelled: { false })
        guard case let .files(outputs) = result, let output = outputs.first else {
            return XCTFail("Kompresi gambar tidak menghasilkan satu file")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(output.pathExtension, "jpg")
        XCTAssertNotEqual(try Data(contentsOf: input), try Data(contentsOf: output))
    }

    func testDocumentCompressionPackagesOriginalFileInZip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroCompression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("proposal.docx")
        try Data("document payload".utf8).write(to: input)

        let result = try CompressionConverter().compress(input: input, temporaryDirectory: root.appendingPathComponent("temp"), ffmpegURL: nil, encoders: [], preset: .balanced, progress: { _ in }, isCancelled: { false })
        guard case let .files(outputs) = result, let output = outputs.first else {
            return XCTFail("Kompresi dokumen tidak menghasilkan ZIP")
        }
        XCTAssertEqual(output.pathExtension, "zip")
        XCTAssertEqual(try Data(contentsOf: output).prefix(2), Data([0x50, 0x4B]))
    }
}
