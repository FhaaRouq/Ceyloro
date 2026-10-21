import XCTest
@testable import CeyloroEngine

final class PortableEngineTests: XCTestCase {
    private let allTargets = Set(PortableTargetFormat.allCases)

    func testDetectionDoesNotDependOnAppleUniformTypeIdentifiers() {
        XCTAssertEqual(PortableFileFormat.detect(url: URL(fileURLWithPath: "/tmp/clip.webm")).kind, .video)
        XCTAssertEqual(PortableFileFormat.detect(url: URL(fileURLWithPath: "/tmp/voice.opus")).kind, .audio)
        XCTAssertEqual(PortableFileFormat.detect(url: URL(fileURLWithPath: "/tmp/report.pdf")).kind, .pdf)
    }

    func testWindowsFFmpegCapabilitiesPlanMediaConversion() throws {
        let capabilities = EngineCapabilities(platform: .windows, backends: [.ffmpeg], supportedTargets: allTargets)
        let request = ConversionRequest(input: URL(fileURLWithPath: "/tmp/clip.mkv"), target: .webm)
        let plan = try ConversionPlanner.plan(request, capabilities: capabilities)

        XCTAssertEqual(plan.backend, .ffmpeg)
        XCTAssertEqual(plan.request.target, .webm)
    }

    func testNativeBackendIsPreferredWhenAvailable() throws {
        let capabilities = EngineCapabilities(platform: .macOS, backends: [.native, .ffmpeg], supportedTargets: allTargets)
        let request = ConversionRequest(input: URL(fileURLWithPath: "/tmp/voice.wav"), target: .m4a)

        XCTAssertEqual(try ConversionPlanner.plan(request, capabilities: capabilities).backend, .native)
    }

    func testUnsupportedTargetIsRejectedBeforeBackendRuns() {
        let capabilities = EngineCapabilities(platform: .windows, backends: [.ffmpeg], supportedTargets: [.mp3])
        let request = ConversionRequest(input: URL(fileURLWithPath: "/tmp/voice.wav"), target: .webm)

        XCTAssertThrowsError(try ConversionPlanner.plan(request, capabilities: capabilities)) { error in
            XCTAssertEqual(error as? PortableConversionError, .unsupportedTarget)
        }
    }
}
