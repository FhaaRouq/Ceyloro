import XCTest
@testable import PomeloCore

final class OutputNamingTests: XCTestCase {
    func testDoesNotOverwriteExistingOutput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PomeloNaming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("photo.heic")
        let existing = directory.appendingPathComponent("photo.jpg")
        FileManager.default.createFile(atPath: existing.path, contents: Data())
        let result = OutputNaming().uniqueURL(for: input, target: .jpg, in: directory)
        XCTAssertEqual(result.lastPathComponent, "photo 2.jpg")
    }

    func testPageSuffixIsStable() {
        let input = URL(fileURLWithPath: "/tmp/report.pdf")
        XCTAssertEqual(OutputNaming().uniqueURL(for: input, target: .png, suffix: "1").lastPathComponent, "report-1.png")
    }
}
