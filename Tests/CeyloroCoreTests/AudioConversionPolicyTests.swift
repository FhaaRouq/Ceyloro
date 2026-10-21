import XCTest
@testable import CeyloroCore

final class AudioConversionPolicyTests: XCTestCase {
    func testNativeTargetsExcludeTheSourceAndUnavailableFormats() {
        let policy = AudioConversionPolicy()
        let targets = policy.targets(for: FileFormat(fileExtension: "aiff", kind: .audio))

        XCTAssertEqual(Set(targets), Set([.m4a, .wav]))
        XCTAssertFalse(targets.contains(.mp3))
        XCTAssertFalse(targets.contains(.aiff))
    }

    func testNonAudioSourcesHaveNoNativeAudioTargets() {
        let policy = AudioConversionPolicy()

        XCTAssertTrue(policy.targets(for: FileFormat(fileExtension: "mp4", kind: .video)).isEmpty)
        XCTAssertTrue(policy.targets(for: FileFormat(fileExtension: "jpg", kind: .image)).isEmpty)
    }
}
