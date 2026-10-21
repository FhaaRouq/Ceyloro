import XCTest
@testable import CeyloroEngine

final class PortableEngineTests: XCTestCase {
    private let allTargets = Set(PortableTargetFormat.allCases)

    func testDetectionDoesNotDependOnAppleUniformTypeIdentifiers() {
        XCTAssertEqual(PortableFileFormat.detect(url: URL(fileURLWithPath: "/tmp/clip.webm")).kind, .video)
        XCTAssertEqual(PortableFileFormat.detect(url: URL(fileURLWithPath: "/tmp/voice.opus")).kind, .audio)
        XCTAssertEqual(PortableFileFormat.detect(url: URL(fileURLWithPath: "/tmp/report.pdf")).kind, .pdf)
    }

    func testDetectionNormalizesEquivalentExtensions() {
        XCTAssertEqual(PortableFileFormat.detect(url: URL(fileURLWithPath: "/tmp/photo.JPEG")).fileExtension, "jpg")
        XCTAssertEqual(PortableFileFormat.detect(url: URL(fileURLWithPath: "/tmp/photo.heif")).fileExtension, "heic")
        XCTAssertEqual(PortableFileFormat.detect(url: URL(fileURLWithPath: "/tmp/photo.tif")).fileExtension, "tiff")
        XCTAssertEqual(PortableTargetFormat.gzip.fileExtension, "tar.gz")
    }

    func testWindowsFFmpegCapabilitiesPlanMediaConversion() throws {
        let capabilities = EngineCapabilities(platform: .windows, backends: [.ffmpeg], supportedTargets: allTargets)
        let request = ConversionRequest(input: URL(fileURLWithPath: "/tmp/clip.mkv"), target: .webm)
        let plan = try ConversionPlanner.plan(request, capabilities: capabilities)

        XCTAssertEqual(plan.backend, .ffmpeg)
        XCTAssertEqual(plan.request.target, .webm)
    }

    func testVideoCanBeConvertedToAudioOnPortableShell() {
        let capabilities = EngineCapabilities(platform: .windows, backends: [.ffmpeg], supportedTargets: allTargets)
        let source = PortableFileFormat(fileExtension: "mov", kind: .video)
        let targets = ConversionPlanner.targets(for: source, capabilities: capabilities)

        XCTAssertTrue(targets.contains(.mp3))
        XCTAssertTrue(targets.contains(.m4a))
        XCTAssertTrue(targets.contains(.wav))
        XCTAssertFalse(targets.contains(.mov))
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

    func testCoordinatorUsesPlannedBackendAndForwardsProgress() async throws {
        let output = URL(fileURLWithPath: "/tmp/output.mp3")
        let backend = StubBackend(backend: .ffmpeg, output: output)
        let capabilities = EngineCapabilities(platform: .windows, backends: [.ffmpeg], supportedTargets: allTargets)
        let coordinator = ConversionCoordinator(capabilities: capabilities, adapters: [backend])
        let request = ConversionRequest(input: URL(fileURLWithPath: "/tmp/input.wav"), target: .mp3)
        let progressValues = LockedValues<Double>()

        let result = try await coordinator.execute(request, progress: { progressValues.append($0) })

        XCTAssertEqual(result, output)
        XCTAssertEqual(progressValues.values, [0.5, 1])
        XCTAssertEqual(backend.convertedRequests.count, 1)
    }

    func testCoordinatorReportsMissingBackendWithoutTouchingInput() async {
        let capabilities = EngineCapabilities(platform: .windows, backends: [.ffmpeg], supportedTargets: allTargets)
        let coordinator = ConversionCoordinator(capabilities: capabilities, adapters: [])
        let request = ConversionRequest(input: URL(fileURLWithPath: "/tmp/input.wav"), target: .mp3)

        do {
            _ = try await coordinator.execute(request)
            XCTFail("Konversi seharusnya gagal tanpa adapter")
        } catch let error as ConversionExecutionError {
            XCTAssertEqual(error, .backendUnavailable(.ffmpeg))
        } catch {
            XCTFail("Error tidak sesuai: \(error)")
        }
    }
}

private final class StubBackend: ConversionBackendAdapter, @unchecked Sendable {
    let backend: ConversionBackend
    let output: URL
    private(set) var convertedRequests: [ConversionRequest] = []

    init(backend: ConversionBackend, output: URL) {
        self.backend = backend
        self.output = output
    }

    func supports(_ request: ConversionRequest) -> Bool {
        request.target == .mp3
    }

    func convert(
        _ request: ConversionRequest,
        progress: @escaping ConversionProgressHandler,
        isCancelled: @escaping ConversionCancellationHandler
    ) async throws -> URL {
        guard !isCancelled() else { throw CancellationError() }
        convertedRequests.append(request)
        progress(0.5)
        progress(1)
        return output
    }
}

private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
