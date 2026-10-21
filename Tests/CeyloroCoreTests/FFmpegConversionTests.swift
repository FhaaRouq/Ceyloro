import XCTest
@testable import CeyloroCore

final class FFmpegConversionTests: XCTestCase {
    func testAudioPolicyIncludesFFmpegFormats() {
        let source = FileFormat(fileExtension: "flac", kind: .audio)
        let targets = FFmpegConversionPolicy().targets(for: source)

        XCTAssertTrue(targets.contains(.mp3))
        XCTAssertFalse(targets.contains(.flac))
    }

    func testVideoCommandUsesExpectedCodecAndOutput() {
        let arguments = FFmpegCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/input.mkv"),
            output: URL(fileURLWithPath: "/output.mp4"),
            target: .mp4
        )

        XCTAssertTrue(arguments.contains("mpeg4"))
        XCTAssertFalse(arguments.contains("libx264"))
        XCTAssertTrue(arguments.contains("+faststart"))
        XCTAssertEqual(arguments.last, "/output.mp4")
    }

    func testUnsupportedSourceHasNoFFmpegTargets() {
        XCTAssertTrue(FFmpegConversionPolicy().targets(for: FileFormat(fileExtension: "srt", kind: .subtitle)).isEmpty)
    }
}
