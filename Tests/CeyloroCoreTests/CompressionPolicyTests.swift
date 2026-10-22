import XCTest
@testable import CeyloroCore

final class CompressionPolicyTests: XCTestCase {
    func testMediaCompressionPreservesSourceExtension() {
        let plan = CompressionPolicy.plan(for: FileFormat(fileExtension: "mp4", kind: .video))
        XCTAssertEqual(plan, CompressionPlan(kind: .video, outputExtension: "mp4", preservesSourceFormat: true))
    }

    func testOfficeDocumentCompressionCreatesZipPlan() {
        let plan = CompressionPolicy.plan(for: FileFormat(fileExtension: "docx", kind: .document))
        XCTAssertEqual(plan, CompressionPlan(kind: .document, outputExtension: "zip", preservesSourceFormat: false))
    }

    func testMixedKindsDoNotCreateOneCompressionPlan() {
        let formats = [
            FileFormat(fileExtension: "jpg", kind: .image),
            FileFormat(fileExtension: "mp4", kind: .video)
        ]
        XCTAssertNil(CompressionPolicy.commonPlan(for: formats))
    }
}
