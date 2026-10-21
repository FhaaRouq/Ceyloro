import XCTest
@testable import CeyloroCore

final class OutputNamingTests: XCTestCase {
    func testDoesNotOverwriteExistingOutput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroNaming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("photo.heic")
        let existing = directory.appendingPathComponent("photo.jpg")
        FileManager.default.createFile(atPath: existing.path, contents: Data())
        let result = OutputNaming().uniqueURL(for: input, target: .jpg, in: directory)
        XCTAssertEqual(result.lastPathComponent, "photo 2.jpg")
    }

    func testPageSuffixIsStable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroNaming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("report.pdf")
        XCTAssertEqual(OutputNaming().uniqueURL(for: input, target: .png, suffix: "01").lastPathComponent, "report-01.png")
    }

    func testPageFileNameUsesTwoDigitsAndThreeFor100Pages() {
        let naming = OutputNaming()
        XCTAssertEqual(naming.pageFileName(baseName: "report", index: 0, total: 9, fileExtension: "png"), "report-01.png")
        XCTAssertEqual(naming.pageFileName(baseName: "report", index: 99, total: 100, fileExtension: "png"), "report-100.png")
    }

    func testUniqueFolderAndZipNamesAvoidCollisions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroNaming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("report"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: directory.appendingPathComponent("report.zip").path, contents: Data())
        XCTAssertEqual(OutputNaming().uniqueFolderURL(baseName: "report", in: directory).lastPathComponent, "report 2")
        XCTAssertEqual(OutputNaming().uniqueURL(baseName: "report", fileExtension: "zip", in: directory).lastPathComponent, "report 2.zip")
    }

    func testUserOutputNameCannotEscapeOutputDirectory() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroNaming-\(UUID().uuidString)")
        let result = OutputNaming().uniqueURL(baseName: "../hasil/tersembunyi", fileExtension: "pdf", in: directory)

        XCTAssertEqual(result.deletingLastPathComponent().path, directory.path)
        XCTAssertEqual(result.lastPathComponent, "..-hasil-tersembunyi.pdf")
    }
}
