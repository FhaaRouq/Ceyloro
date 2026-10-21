import XCTest
@testable import PomeloCore

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

    func testUnsupportedKindHasNoTargets() {
        XCTAssertTrue(ConversionMatrix().targets(for: FileFormat(fileExtension: "mp4", kind: .video)).isEmpty)
    }

    func testEquivalentImageExtensionsAreCanonicalized() {
        XCTAssertEqual(FileFormat(fileExtension: ".jpeg", kind: .image).fileExtension, "jpg")
        XCTAssertEqual(FileFormat(fileExtension: "tif", kind: .image).fileExtension, "tiff")
        XCTAssertEqual(FileFormat(fileExtension: "heif", kind: .image).fileExtension, "heic")
    }
}
