import XCTest
@testable import CeyloroCore

final class FFmpegConversionTests: XCTestCase {
    func testAudioPolicyIncludesFFmpegFormats() {
        let source = FileFormat(fileExtension: "flac", kind: .audio)
        let targets = FFmpegConversionPolicy().targets(for: source)

        XCTAssertTrue(targets.contains(.mp3))
        XCTAssertFalse(targets.contains(.flac))
    }

    func testVideoPolicyIncludesAudioExtractionTargets() {
        let source = FileFormat(fileExtension: "mp4", kind: .video)
        let targets = FFmpegConversionPolicy().targets(for: source)

        XCTAssertTrue(targets.contains(.mp3))
        XCTAssertTrue(targets.contains(.m4a))
        XCTAssertTrue(targets.contains(.wav))
        XCTAssertFalse(targets.contains(.mp4))
    }

    func testVideoToAudioCommandDisablesVideoStream() {
        let arguments = FFmpegCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/input.mp4"),
            output: URL(fileURLWithPath: "/output.mp3"),
            target: .mp3
        )

        XCTAssertTrue(arguments.contains("-vn"))
        XCTAssertTrue(arguments.contains("-c:a"))
        XCTAssertTrue(arguments.contains("libshine"))
        XCTAssertTrue(arguments.contains("192k"))
        XCTAssertEqual(arguments.last, "/output.mp3")
    }

    func testOggCommandEnablesExperimentalVorbisAndStereoCompatibility() {
        let arguments = FFmpegCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/input.mp4"),
            output: URL(fileURLWithPath: "/output.ogg"),
            target: .ogg
        )

        XCTAssertTrue(arguments.contains("-strict"))
        XCTAssertTrue(arguments.contains("-2"))
        XCTAssertTrue(arguments.contains("-ac"))
        XCTAssertTrue(arguments.contains("2"))
        XCTAssertTrue(arguments.contains("vorbis"))
    }

    func testOpusCommandEnablesExperimentalEncoder() {
        let arguments = FFmpegCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/input.mp3"),
            output: URL(fileURLWithPath: "/output.opus"),
            target: .opus
        )

        XCTAssertTrue(arguments.contains("-strict"))
        XCTAssertTrue(arguments.contains("-2"))
        XCTAssertTrue(arguments.contains("opus"))
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
        XCTAssertTrue(arguments.contains("-progress"))
        XCTAssertTrue(arguments.contains("pipe:1"))
    }

    func testUnsupportedSourceHasNoFFmpegTargets() {
        XCTAssertTrue(FFmpegConversionPolicy().targets(for: FileFormat(fileExtension: "srt", kind: .subtitle)).isEmpty)
    }

    func testPolicyValidatesEncodersWhenProvided() {
        let encoders: Set<String> = ["libmp3lame", "aac", "mpeg4"]
        XCTAssertTrue(FFmpegConversionPolicy.supports(target: .mp3, encoders: encoders))
        XCTAssertTrue(FFmpegConversionPolicy.supports(target: .m4a, encoders: encoders))
        XCTAssertTrue(FFmpegConversionPolicy.supports(target: .mp4, encoders: encoders))
        // WebM needs vp9/vp8 and opus/vorbis
        XCTAssertFalse(FFmpegConversionPolicy.supports(target: .webm, encoders: encoders))
    }

    func testAdaptiveArgumentsPreferAvailableEncoders() {
        let lameArgs = FFmpegCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/input.wav"),
            output: URL(fileURLWithPath: "/output.mp3"),
            target: .mp3,
            encoders: ["libmp3lame"]
        )
        XCTAssertTrue(lameArgs.contains("libmp3lame"))

        let webmArgs = FFmpegCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/input.mp4"),
            output: URL(fileURLWithPath: "/output.webm"),
            target: .webm,
            encoders: ["libvpx-vp9", "opus"]
        )
        XCTAssertTrue(webmArgs.contains("libvpx-vp9"))
    }
}
