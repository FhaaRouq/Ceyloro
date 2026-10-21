import XCTest
@testable import CeyloroCore

final class VideoConversionPolicyTests: XCTestCase {
    func testNativeTargetsExcludeTheSourceAndUnavailableFormats() {
        let policy = VideoConversionPolicy()
        let targets = policy.targets(for: FileFormat(fileExtension: "mov", kind: .video))

        XCTAssertEqual(targets, [.mp4])
        XCTAssertFalse(targets.contains(.mkv))
        XCTAssertFalse(targets.contains(.mov))
    }

    func testNonVideoSourcesHaveNoNativeVideoTargets() {
        let policy = VideoConversionPolicy()

        XCTAssertTrue(policy.targets(for: FileFormat(fileExtension: "mp3", kind: .audio)).isEmpty)
        XCTAssertTrue(policy.targets(for: FileFormat(fileExtension: "jpg", kind: .image)).isEmpty)
    }
}
