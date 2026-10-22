import XCTest
@testable import CeyloroCore

final class DocumentConversionPolicyTests: XCTestCase {
    private let policy = DocumentConversionPolicy()

    func testOfficeAndTextSourcesExposeOnlyPhaseATargets() {
        XCTAssertEqual(policy.targets(for: FileFormat(fileExtension: "doc", kind: .document)), [.pdf, .docx])
        XCTAssertEqual(policy.targets(for: FileFormat(fileExtension: "docx", kind: .document)), [.pdf, .odt, .rtf, .md, .html, .txt])
        XCTAssertEqual(policy.targets(for: FileFormat(fileExtension: "md", kind: .document)), [.docx, .pdf])
    }

    func testSpreadsheetsExposePDFAndCSVTargets() {
        XCTAssertEqual(policy.targets(for: FileFormat(fileExtension: "xlsx", kind: .document)), [.pdf, .csv])
        XCTAssertEqual(policy.targets(for: FileFormat(fileExtension: "ods", kind: .document)), [.pdf, .csv])
    }

    func testSlidesExposePDFAndPNGTargets() {
        XCTAssertEqual(policy.targets(for: FileFormat(fileExtension: "pptx", kind: .document)), [.pdf, .png])
        XCTAssertEqual(policy.targets(for: FileFormat(fileExtension: "odp", kind: .document)), [.pdf, .png])
    }

    func testUnsupportedDocumentExtensionIsEmpty() {
        XCTAssertTrue(policy.targets(for: FileFormat(fileExtension: "pages", kind: .document)).isEmpty)
    }

    func testTextPDFExposesBestEffortDOCXTarget() {
        XCTAssertEqual(policy.targets(for: FileFormat(fileExtension: "pdf", kind: .pdf)), [.docx])
    }
}
