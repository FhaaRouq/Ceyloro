import Foundation
import XCTest
@testable import Ceyloro

final class FFmpegConverterTests: XCTestCase {
    func testAnimatedGIFOffersVideoTargetsWhenFFmpegIsAvailable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroGIF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = root.appendingPathComponent("ffmpeg")
        let gif = root.appendingPathComponent("animation.gif")
        try Data("fixture".utf8).write(to: gif)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let targets = FFmpegConverter().supportedTargets(for: [gif], candidates: [.mp4, .jpg, .gif], ffmpegURL: fake)

        XCTAssertEqual(targets, [.mp4])
    }

    func testExecutableBridgeProducesOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroFFmpeg-\(UUID().uuidString)")
        let fake = root.appendingPathComponent("ffmpeg")
        let input = root.appendingPathComponent("input.flac")
        let temporary = root.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("fixture".utf8).write(to: input)
        let script = "#!/bin/sh\ninput=\"\"\noutput=\"\"\nprevious=\"\"\nfor arg in \"$@\"; do\n  if [ \"$previous\" = \"-i\" ]; then input=\"$arg\"; fi\n  output=\"$arg\"\n  previous=\"$arg\"\ndone\ncp \"$input\" \"$output\"\n"
        try Data(script.utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let result = try FFmpegConverter().convert(input: input, target: .mp3, temporaryDirectory: temporary, ffmpegURL: fake, progress: { _ in }, isCancelled: { false })
        let output = try XCTUnwrap(result.first)
        XCTAssertEqual(try Data(contentsOf: output), Data("fixture".utf8))
    }

    func testExtractDiagnosticReasonFiltersBannerAndCapturesError() {
        let sampleStderr = """
        ffmpeg version 6.1.1 Copyright (c) 2000-2023 the FFmpeg developers
          built with Apple clang version 15.0.0
          configuration: --prefix=/usr/local --enable-gpl
          libavutil      58. 29.100 / 58. 29.100
          libavcodec     60. 31.102 / 60. 31.102
        [mov,mp4,m4a,3gp,3g2,mj2 @ 0x7fa281804000] moov atom not found
        input.mp4: Invalid data found when processing input
        Conversion failed!
        """
        let reason = FFmpegConverter.extractDiagnosticReason(from: sampleStderr)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("Invalid data found") == true || reason?.contains("Conversion failed") == true)
    }

    func testFFmpegFailureAttachesDiagnosticReasonToError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroFFmpegFail-\(UUID().uuidString)")
        let fake = root.appendingPathComponent("ffmpeg")
        let input = root.appendingPathComponent("broken.mp4")
        let temporary = root.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("dummy".utf8).write(to: input)
        let script = "#!/bin/sh\n>&2 echo \"[mp4 @ 0x123] moov atom not found\"\n>&2 echo \"Conversion failed!\"\nexit 1\n"
        try Data(script.utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        XCTAssertThrowsError(try FFmpegConverter().convert(input: input, target: .mp3, temporaryDirectory: temporary, ffmpegURL: fake, progress: { _ in }, isCancelled: { false })) { error in
            guard case let .ffmpegFailed(reason) = error as? ConversionError else {
                return XCTFail("Expected ConversionError.ffmpegFailed but got \(error)")
            }
            XCTAssertTrue(reason?.contains("Conversion failed!") == true || reason?.contains("moov atom not found") == true)
            XCTAssertTrue(error.localizedDescription.contains("FFmpeg gagal memproses file ini:"))
        }
    }
}
