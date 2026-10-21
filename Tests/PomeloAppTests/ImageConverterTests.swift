import AppKit
import CoreGraphics
import ImageIO
import PDFKit
import PomeloCore
import UniformTypeIdentifiers
import XCTest
@testable import Pomelo

final class ImageConverterTests: XCTestCase {
    func testJPEGExifOrientationIsAppliedWhenConvertingToJPG() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PomeloImage-\(UUID().uuidString)")
        let sourceURL = root.appendingPathComponent("portrait-source.jpg")
        let temporaryDirectory = root.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 60, height: 30, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(sourceURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw XCTSkip("ImageIO JPEG fixture is unavailable on this system")
        }

        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let outputs = try ImageConverter().convert(input: sourceURL, target: .jpg, temporaryDirectory: temporaryDirectory, progress: { _ in }, isCancelled: { false })
        let output = try XCTUnwrap(outputs.first)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let width = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?)[kCGImagePropertyPixelWidth] as? Int
        let height = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?)[kCGImagePropertyPixelHeight] as? Int

        XCTAssertEqual(width, 30)
        XCTAssertEqual(height, 60)
    }

    func testMergedPDFKeepsInputOrderInPageSizes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PomeloPDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let landscape = try makeImage(at: root.appendingPathComponent("IMG_2.png"), width: 1200, height: 600)
        let portrait = try makeImage(at: root.appendingPathComponent("IMG_10.png"), width: 600, height: 1200)
        let output = root.appendingPathComponent("merged.pdf")
        try PDFBuilder.build(
            images: [landscape, portrait],
            outputURL: output,
            options: PDFMergeOptions(pageSize: .matchImage, margin: .none, quality: .original),
            progress: { _ in },
            isCancelled: { false }
        )
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, 2)
        let first = try XCTUnwrap(document.page(at: 0))
        let second = try XCTUnwrap(document.page(at: 1))
        XCTAssertEqual(first.bounds(for: .mediaBox).width, 842, accuracy: 0.5)
        XCTAssertEqual(first.bounds(for: .mediaBox).height, 421, accuracy: 0.5)
        XCTAssertEqual(second.bounds(for: .mediaBox).width, 421, accuracy: 0.5)
        XCTAssertEqual(second.bounds(for: .mediaBox).height, 842, accuracy: 0.5)
    }

    func testTenImagesProduceMeasuredBalancedPDF() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PomeloPDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let images = try (0..<10).map { index in
            try makeImage(at: root.appendingPathComponent("image-\(index).png"), width: 1200, height: 800)
        }
        let output = root.appendingPathComponent("ten-images.pdf")
        try PDFBuilder.build(images: images, outputURL: output, options: PDFMergeOptions(), progress: { _ in }, isCancelled: { false })
        let size = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber
        XCTAssertNotNil(size)
        if let size {
            print("Measured balanced PDF size for 10 images: \(size.intValue) bytes")
        }
        XCTAssertLessThan(size?.intValue ?? Int.max, 15 * 1024 * 1024)
    }

    func testRotatedPDFPageIsRenderedWithPageOrientationOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PomeloPDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("rotated.pdf")
        let outputDirectory = root.appendingPathComponent("output", isDirectory: true)
        let imageURL = try makeImage(at: root.appendingPathComponent("source.png"), width: 60, height: 120)
        let image = try XCTUnwrap(NSImage(contentsOf: imageURL))
        let page = try XCTUnwrap(PDFPage(image: image))
        page.rotation = 90
        let document = PDFDocument()
        document.insert(page, at: 0)
        XCTAssertTrue(document.write(to: source))

        let result = try ImageConverter().convert(input: source, target: .png, temporaryDirectory: outputDirectory, progress: { _ in }, isCancelled: { false })
        let output = try XCTUnwrap(result.first)
        let outputSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(outputSource, 0, nil) as NSDictionary?)
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertGreaterThan(width, height)
    }

    func testScannedPDFToTextReportsEmptyText() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PomeloPDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = try makeImage(at: root.appendingPathComponent("source.png"), width: 100, height: 100)
        let source = root.appendingPathComponent("scan.pdf")
        try PDFBuilder.build(images: [imageURL], outputURL: source, options: .init(), progress: { _ in }, isCancelled: { false })

        XCTAssertThrowsError(try ImageConverter().convert(input: source, target: .txt, temporaryDirectory: root.appendingPathComponent("output"), progress: { _ in }, isCancelled: { false })) { error in
            guard case .noText = error as? ConversionError else {
                return XCTFail("Expected the empty-PDF text error, got \(error)")
            }
        }
    }

    private func makeImage(at url: URL, width: Int, height: Int) throws -> URL {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw XCTSkip("ImageIO fixture is unavailable on this system")
        }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
