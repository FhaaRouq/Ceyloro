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
        XCTAssertTrue(arguments.contains("libmp3lame"))
        XCTAssertTrue(arguments.contains("192k"))
        XCTAssertTrue(arguments.contains("-protocol_whitelist"))
        XCTAssertTrue(arguments.contains("file,crypto,data"))
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
        let probe = ProbeResult.success(encoders: encoders)
        XCTAssertTrue(FFmpegConversionPolicy.supports(target: .mp3, probe: probe))
        XCTAssertTrue(FFmpegConversionPolicy.supports(target: .m4a, probe: probe))
        XCTAssertTrue(FFmpegConversionPolicy.supports(target: .mp4, probe: probe))
        // WebM needs vp9/vp8 and opus/vorbis
        XCTAssertFalse(FFmpegConversionPolicy.supports(target: .webm, probe: probe))
    }

    // MARK: - B3 regression: ProbeResult.failed dan .unknown harus menolak semua target

    func testProbeFailedRejectsAllTargets() {
        XCTAssertFalse(FFmpegConversionPolicy.supports(target: .mp3, probe: .failed))
        XCTAssertFalse(FFmpegConversionPolicy.supports(target: .mp4, probe: .failed))
        XCTAssertFalse(FFmpegConversionPolicy.supports(target: .gif, probe: .failed))
    }

    func testProbeUnknownRejectsAllTargets() {
        XCTAssertFalse(FFmpegConversionPolicy.supports(target: .mp3, probe: .unknown))
        XCTAssertFalse(FFmpegConversionPolicy.supports(target: .mp4, probe: .unknown))
        XCTAssertFalse(FFmpegConversionPolicy.supports(target: .gif, probe: .unknown))
    }

    func testProbeSuccessWithMissingEncoderRejectsTarget() {
        // Encoder tersedia: hanya aac — MP3 tidak boleh ditawarkan
        let probe = ProbeResult.success(encoders: ["aac"])
        XCTAssertFalse(FFmpegConversionPolicy.supports(target: .mp3, probe: probe))
        XCTAssertTrue(FFmpegConversionPolicy.supports(target: .m4a, probe: probe))
        // MP4 butuh video encoder (mpeg4/libx264/h264) — tidak ada → ditolak
        XCTAssertFalse(FFmpegConversionPolicy.supports(target: .mp4, probe: probe))
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

    func testVideoCompressionUsesModernCodec() {
        // AC-5: Video MP4 menggunakan encoder H.264 modern, bukan mpeg4.
        let vtArgs = FFmpegCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/input.mp4"),
            output: URL(fileURLWithPath: "/output.mp4"),
            target: .mp4,
            encoders: ["h264_videotoolbox", "mpeg4", "aac"],
            compression: .balanced
        )
        XCTAssertTrue(vtArgs.contains("h264_videotoolbox"))
        XCTAssertFalse(vtArgs.contains("mpeg4"))

        let x264Args = FFmpegCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/input.mp4"),
            output: URL(fileURLWithPath: "/output.mp4"),
            target: .mp4,
            encoders: ["libx264", "mpeg4", "aac"],
            compression: .smaller
        )
        XCTAssertTrue(x264Args.contains("libx264"))
        XCTAssertFalse(x264Args.contains("mpeg4"))
        XCTAssertTrue(x264Args.contains("-crf"))
        XCTAssertTrue(x264Args.contains("28"))
    }

    func testVideoPolicySupportsVideoToolbox() {
        let probe = ProbeResult.success(encoders: ["h264_videotoolbox", "aac"])
        XCTAssertTrue(FFmpegConversionPolicy.supports(target: .mp4, probe: probe))
        XCTAssertTrue(FFmpegConversionPolicy.supports(target: .mov, probe: probe))
        XCTAssertTrue(FFmpegConversionPolicy.supports(target: .mkv, probe: probe))
    }
}

