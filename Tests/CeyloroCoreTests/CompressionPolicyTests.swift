import XCTest
@testable import CeyloroCore

final class CompressionPolicyTests: XCTestCase {
    func testMediaCompressionPreservesSourceExtension() {
        let plan = CompressionPolicy.plan(for: FileFormat(fileExtension: "mp4", kind: .video))
        XCTAssertEqual(plan, CompressionPlan(kind: .video, outputExtension: "mp4", preservesSourceFormat: true))
    }

    func testOfficeDocumentCompressionPreservesFormat() {
        let plan = CompressionPolicy.plan(for: FileFormat(fileExtension: "docx", kind: .document))
        // AC-6: Setelah Fase 3, .docx dikompresi secara in-place sehingga preservesSourceFormat: true
        // dan outputExtension tetap "docx" (bukan "zip" semu)
        XCTAssertEqual(plan, CompressionPlan(kind: .document, outputExtension: "docx", preservesSourceFormat: true))
    }

    func testMixedKindsDoNotCreateOneCompressionPlan() {
        let formats = [
            FileFormat(fileExtension: "jpg", kind: .image),
            FileFormat(fileExtension: "mp4", kind: .video)
        ]
        XCTAssertNil(CompressionPolicy.commonPlan(for: formats))
    }
}
