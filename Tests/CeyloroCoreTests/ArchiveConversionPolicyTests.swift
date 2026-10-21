import XCTest
@testable import CeyloroCore

final class ArchiveConversionPolicyTests: XCTestCase {
    func testNativeTargetsExcludeTheSourceAndUnsupportedFormats() {
        let policy = ArchiveConversionPolicy()
        let targets = policy.targets(for: FileFormat(fileExtension: "zip", kind: .archive))

        XCTAssertEqual(Set(targets), Set([.tar, .gzip]))
        XCTAssertFalse(targets.contains(.zip))
    }

    func testNonArchiveSourcesHaveNoNativeArchiveTargets() {
        let policy = ArchiveConversionPolicy()

        XCTAssertTrue(policy.targets(for: FileFormat(fileExtension: "mp4", kind: .video)).isEmpty)
        XCTAssertTrue(policy.targets(for: FileFormat(fileExtension: "txt", kind: .document)).isEmpty)
        XCTAssertTrue(policy.targets(for: FileFormat(fileExtension: "rar", kind: .archive)).isEmpty)
        XCTAssertTrue(policy.targets(for: FileFormat(fileExtension: "7z", kind: .archive)).isEmpty)
    }

    func testUnsupportedArchiveSourcesAreFlagged() {
        let policy = ArchiveConversionPolicy()
        XCTAssertTrue(policy.isSupported(source: FileFormat(fileExtension: "zip", kind: .archive)))
        XCTAssertFalse(policy.isSupported(source: FileFormat(fileExtension: "rar", kind: .archive)))
        XCTAssertFalse(policy.isSupported(source: FileFormat(fileExtension: "7z", kind: .archive)))
    }
}
