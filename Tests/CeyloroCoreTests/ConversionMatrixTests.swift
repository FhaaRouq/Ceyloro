import XCTest
@testable import CeyloroCore

final class ConversionMatrixTests: XCTestCase {
    func testImageTargetsExcludeSameExtension() {
        let matrix = ConversionMatrix()
        let targets = matrix.targets(for: FileFormat(fileExtension: "jpg", kind: .image))
        XCTAssertFalse(targets.contains(.jpg))
        XCTAssertTrue(targets.contains(.png))
        XCTAssertTrue(targets.contains(.pdf))
    }

    func testMixedSelectionUsesIntersection() {
        let matrix = ConversionMatrix()
        let sources = [
            FileFormat(fileExtension: "jpg", kind: .image),
            FileFormat(fileExtension: "png", kind: .image)
        ]
        XCTAssertEqual(Set(matrix.commonTargets(for: sources)), Set([.heic, .tiff, .pdf]))
    }

    func testDocumentTargetsFollowPhaseAMatrix() {
        let matrix = ConversionMatrix()
        XCTAssertEqual(Set(matrix.targets(for: FileFormat(fileExtension: "docx", kind: .document))), Set([.pdf, .odt, .rtf, .md, .html, .txt]))
        XCTAssertEqual(Set(matrix.targets(for: FileFormat(fileExtension: "xlsx", kind: .document))), Set([.pdf]))
        XCTAssertEqual(Set(matrix.targets(for: FileFormat(fileExtension: "md", kind: .document))), Set([.docx, .pdf]))
    }

    func testMediaTargetsExcludeTheSourceExtension() {
        let matrix = ConversionMatrix()
        let audioTargets = matrix.targets(for: FileFormat(fileExtension: "mp3", kind: .audio))
        let videoTargets = matrix.targets(for: FileFormat(fileExtension: "mp4", kind: .video))
        XCTAssertFalse(audioTargets.contains(.mp3))
        XCTAssertTrue(audioTargets.contains(.flac))
        XCTAssertFalse(videoTargets.contains(.mp4))
        XCTAssertTrue(videoTargets.contains(.mov))
        XCTAssertTrue(videoTargets.contains(.mp3))
        XCTAssertTrue(videoTargets.contains(.wav))
    }

    func testSubtitleAndArchiveTargetsAreCategorized() {
        let matrix = ConversionMatrix()
        XCTAssertEqual(Set(matrix.targets(for: FileFormat(fileExtension: "srt", kind: .subtitle))), Set([.vtt, .txt]))
        XCTAssertEqual(Set(matrix.targets(for: FileFormat(fileExtension: "zip", kind: .archive))), Set([.tar, .gzip]))
        XCTAssertTrue(matrix.targets(for: FileFormat(fileExtension: "rar", kind: .archive)).isEmpty)
        XCTAssertTrue(matrix.targets(for: FileFormat(fileExtension: "7z", kind: .archive)).isEmpty)
    }

    func testEquivalentImageExtensionsAreCanonicalized() {
        XCTAssertEqual(FileFormat(fileExtension: ".jpeg", kind: .image).fileExtension, "jpg")
        XCTAssertEqual(FileFormat(fileExtension: "tif", kind: .image).fileExtension, "tiff")
        XCTAssertEqual(FileFormat(fileExtension: "heif", kind: .image).fileExtension, "heic")
    }
}
