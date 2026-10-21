import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import ImageIO
import PDFKit
import CeyloroCore
import UniformTypeIdentifiers
import XCTest
@testable import Ceyloro

final class ImageConverterTests: XCTestCase {
    func testNativeVideoCanExportToMOVWhenSupported() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroVideo-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source.mp4")
        let temporaryDirectory = root.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await makeVideo(at: source)

        let converter = VideoConverter()
        guard converter.supportedTargets(for: [source], candidates: [.mov]).contains(.mov) else {
            throw XCTSkip("AVFoundation tidak menawarkan ekspor MOV pada sistem ini")
        }

        let result = try converter.convert(input: source, target: .mov, temporaryDirectory: temporaryDirectory, progress: { _ in }, isCancelled: { false })
        let output = try XCTUnwrap(result.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(size, 0)
        XCTAssertNotNil(AVAsset(url: output))
    }

    func testNativeAudioCanExportToM4AWhenSupported() throws {
        let source = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
        guard FileManager.default.isReadableFile(atPath: source.path) else {
            throw XCTSkip("Audio fixture macOS tidak tersedia")
        }
        let converter = AudioConverter()
        guard converter.supportedTargets(for: [source], candidates: [.m4a]).contains(.m4a) else {
            throw XCTSkip("AVFoundation tidak menawarkan ekspor M4A pada sistem ini")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroAudio-\(UUID().uuidString)")
        let temporaryDirectory = root.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try converter.convert(input: source, target: .m4a, temporaryDirectory: temporaryDirectory, progress: { _ in }, isCancelled: { false })
        let output = try XCTUnwrap(result.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(size, 0)
        XCTAssertNotNil(try AVAudioFile(forReading: output))
    }

    func testNativeAudioCanDecodeToWAVPCMWhenSupported() throws {
        let source = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
        guard FileManager.default.isReadableFile(atPath: source.path) else {
            throw XCTSkip("Audio fixture macOS tidak tersedia")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroAudio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let temporaryDirectory = root.appendingPathComponent("temporary", isDirectory: true)
        let converter = AudioConverter()
        guard converter.supportedTargets(for: [source], candidates: [.wav]).contains(.wav) else {
            throw XCTSkip("PCM WAV tidak tersedia pada sistem ini")
        }

        let result = try converter.convert(input: source, target: .wav, temporaryDirectory: temporaryDirectory, progress: { _ in }, isCancelled: { false })
        let output = try XCTUnwrap(result.first)
        XCTAssertEqual(output.pathExtension, "wav")
        XCTAssertGreaterThan(try AVAudioFile(forReading: output).length, 0)
    }

    func testJPEGExifOrientationIsAppliedWhenConvertingToJPG() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroImage-\(UUID().uuidString)")
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

        let sourceExif: [CFString: Any] = [kCGImagePropertyExifUserComment: "Ceyloro test metadata"]
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: sourceExif
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let outputs = try ImageConverter().convert(input: sourceURL, target: .jpg, temporaryDirectory: temporaryDirectory, progress: { _ in }, isCancelled: { false })
        let output = try XCTUnwrap(outputs.first)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?)
        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int

        XCTAssertEqual(width, 30)
        XCTAssertEqual(height, 60)
        let outputExif = properties[kCGImagePropertyExifDictionary] as? NSDictionary
        XCTAssertEqual(outputExif?[kCGImagePropertyExifUserComment] as? String, "Ceyloro test metadata")
    }

    func testMergedPDFKeepsInputOrderInPageSizes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroPDF-\(UUID().uuidString)")
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroPDF-\(UUID().uuidString)")
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroPDF-\(UUID().uuidString)")
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroPDF-\(UUID().uuidString)")
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

    private func makeVideo(at url: URL) async throws {
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw XCTSkip("AVAssetWriter MP4 tidak tersedia")
        }
        let width = 160
        let height = 120
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(input) else { throw XCTSkip("AVAssetWriter input tidak tersedia") }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "CeyloroTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Video fixture gagal dimulai."])
        }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<3 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard let pixelBuffer = makePixelBuffer(width: width, height: height, frame: frame),
                  adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 3)) else {
                writer.cancelWriting()
                throw writer.error ?? NSError(domain: "CeyloroTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Video fixture gagal ditulis."])
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "CeyloroTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Video fixture gagal diselesaikan."])
        }
    }

    private func makePixelBuffer(width: Int, height: Int, frame: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return nil }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = UInt8((x + frame * 20) % 255)
                bytes[offset + 1] = UInt8((y + frame * 30) % 255)
                bytes[offset + 2] = UInt8((frame * 60) % 255)
                bytes[offset + 3] = 255
            }
        }
        return pixelBuffer
    }
}
