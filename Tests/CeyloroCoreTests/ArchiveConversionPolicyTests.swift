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
    }
}
