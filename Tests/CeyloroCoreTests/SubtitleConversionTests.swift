import XCTest
@testable import CeyloroCore

final class SubtitleConversionTests: XCTestCase {
    func testSRTToVTTConvertsClockAndRemovesCueNumbers() throws {
        let source = "1\n00:00:01,250 --> 00:00:02,500\nHalo\n\n2\n00:01:02,000 --> 00:01:03,100\nDunia"

        let result = try SubtitleTranscoder.convert(source, from: .srt, to: .vtt)

        XCTAssertTrue(result.hasPrefix("WEBVTT\n\n"))
        XCTAssertTrue(result.contains("00:00:01.250 --> 00:00:02.500"))
        XCTAssertTrue(result.contains("Halo"))
        XCTAssertFalse(result.contains("\n1\n"))
    }

    func testVTTToSRTPreservesTextAndCueSettings() throws {
        let source = "WEBVTT\n\n00:00:01.000 --> 00:00:02.000 align:start\nHalo\nDunia"

        let result = try SubtitleTranscoder.convert(source, from: .vtt, to: .srt)

        XCTAssertTrue(result.hasPrefix("1\n00:00:01,000 --> 00:00:02,000\n"))
        XCTAssertTrue(result.contains("Halo\nDunia"))
        XCTAssertFalse(result.contains("align:start"))
    }

    func testInvalidSubtitleIsRejected() {
        XCTAssertThrowsError(try SubtitleTranscoder.parse("bukan subtitle", format: .srt)) { error in
            XCTAssertEqual(error as? SubtitleConversionError, .invalidCue)
        }
    }

    func testVTTSkipsMetadataBlocksAndAcceptsHeaderText() throws {
        let source = "WEBVTT - Ceyloro\n\nNOTE\nmetadata\n\nSTYLE\n::cue { color: white; }\n\ncue-1\n00:00:01.000 --> 00:00:02.000\nHalo"

        let cues = try SubtitleTranscoder.parse(source, format: .vtt)

        XCTAssertEqual(cues, [SubtitleCue(startMilliseconds: 1_000, endMilliseconds: 2_000, text: "Halo")])
    }
}
