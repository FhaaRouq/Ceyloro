import Foundation
import XCTest
@testable import Ceyloro

final class FFmpegConverterTests: XCTestCase {
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
}
