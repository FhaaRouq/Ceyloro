import Foundation

/// Platform shell yang menjalankan engine Ceyloro.
public enum CeyloroPlatform: String, Codable, CaseIterable, Sendable {
    case macOS
    case windows
}

/// Backend yang melakukan pekerjaan konversi. UI tidak boleh bergantung langsung
/// pada AVFoundation, AppKit, WinRT, atau proses FFmpeg.
public enum ConversionBackend: String, Codable, CaseIterable, Sendable {
    case native
    case ffmpeg
}

public enum PortableMediaKind: String, Codable, CaseIterable, Sendable {
    case image
    case pdf
    case audio
    case video
    case document
    case subtitle
    case archive
    case unknown
}

public struct PortableFileFormat: Hashable, Codable, Sendable {
    public let fileExtension: String
    public let kind: PortableMediaKind

    public init(fileExtension: String, kind: PortableMediaKind) {
        self.fileExtension = fileExtension
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        self.kind = kind
    }

    public static func detect(url: URL) -> Self {
        let ext = url.pathExtension.lowercased()
        let image = ["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "bmp", "gif", "avif", "jfif"]
        let audio = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
        let video = ["mp4", "mov", "mkv", "webm", "avi", "wmv"]
        let documents = ["pdf", "doc", "docx", "rtf", "txt", "md", "pages", "xls", "xlsx", "ppt", "pptx"]
        let subtitles = ["srt", "vtt"]
        let archives = ["zip", "tar", "gz", "gzip", "rar", "7z"]

        if image.contains(ext) { return Self(fileExtension: ext, kind: .image) }
        if audio.contains(ext) { return Self(fileExtension: ext, kind: .audio) }
        if video.contains(ext) { return Self(fileExtension: ext, kind: .video) }
        if documents.contains(ext) { return Self(fileExtension: ext, kind: ext == "pdf" ? .pdf : .document) }
        if subtitles.contains(ext) { return Self(fileExtension: ext, kind: .subtitle) }
        if archives.contains(ext) { return Self(fileExtension: ext, kind: .archive) }
        return Self(fileExtension: ext, kind: .unknown)
    }
}

public enum PortableTargetFormat: String, Codable, CaseIterable, Sendable {
    case jpg, png, heic, tiff, pdf, txt
    case mp3, m4a, wav, flac, ogg, opus, aiff
    case mp4, mov, mkv, webm, avi, wmv, gif
    case srt, vtt, zip, tar, gzip

    public var fileExtension: String { rawValue }
}

public struct EngineCapabilities: Equatable, Codable, Sendable {
    public let platform: CeyloroPlatform
    public let backends: Set<ConversionBackend>
    public let supportedTargets: Set<PortableTargetFormat>

    public init(platform: CeyloroPlatform, backends: Set<ConversionBackend>, supportedTargets: Set<PortableTargetFormat>) {
        self.platform = platform
        self.backends = backends
        self.supportedTargets = supportedTargets
    }

    public func canConvert(to target: PortableTargetFormat) -> Bool {
        supportedTargets.contains(target) && !backends.isEmpty
    }
}

public struct ConversionRequest: Equatable, Codable, Sendable {
    public let input: URL
    public let target: PortableTargetFormat
    public let outputDirectory: URL?

    public init(input: URL, target: PortableTargetFormat, outputDirectory: URL? = nil) {
        self.input = input
        self.target = target
        self.outputDirectory = outputDirectory
    }
}

public struct ConversionPlan: Equatable, Codable, Sendable {
    public let request: ConversionRequest
    public let backend: ConversionBackend

    public init(request: ConversionRequest, backend: ConversionBackend) {
        self.request = request
        self.backend = backend
    }
}

public enum PortableConversionError: Error, Equatable, Sendable {
    case unsupportedSource
    case unsupportedTarget
    case noBackend
}

public enum ConversionPlanner {
    public static func targets(for source: PortableFileFormat, capabilities: EngineCapabilities) -> [PortableTargetFormat] {
        let candidates: [PortableTargetFormat]
        switch source.kind {
        case .image: candidates = [.jpg, .png, .heic, .tiff, .pdf]
        case .pdf: candidates = [.jpg, .png, .txt]
        case .audio: candidates = [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff]
        case .video: candidates = [.mp4, .mov, .mkv, .webm, .avi, .wmv, .gif]
        case .subtitle: candidates = [.srt, .vtt, .txt]
        case .archive: candidates = [.zip, .tar, .gzip]
        case .document, .unknown: candidates = []
        }
        return candidates.filter { $0.fileExtension != source.fileExtension && capabilities.canConvert(to: $0) }
    }

    public static func plan(_ request: ConversionRequest, capabilities: EngineCapabilities) throws -> ConversionPlan {
        let source = PortableFileFormat.detect(url: request.input)
        guard source.kind != .unknown else { throw PortableConversionError.unsupportedSource }
        guard targets(for: source, capabilities: capabilities).contains(request.target) else {
            let error: PortableConversionError = capabilities.supportedTargets.contains(request.target) ? .noBackend : .unsupportedTarget
            throw error
        }
        let backend: ConversionBackend = capabilities.backends.contains(.native) ? .native : .ffmpeg
        return ConversionPlan(request: request, backend: backend)
    }
}

public typealias ConversionProgressHandler = @Sendable (Double) -> Void
public typealias ConversionCancellationHandler = @Sendable () -> Bool

/// Adapter yang diimplementasikan oleh shell/platform. Implementasi native
/// macOS, native Windows, dan FFmpeg dapat hidup terpisah tanpa mengubah planner.
public protocol ConversionBackendAdapter: Sendable {
    var backend: ConversionBackend { get }
    func supports(_ request: ConversionRequest) -> Bool
    func convert(
        _ request: ConversionRequest,
        progress: @escaping ConversionProgressHandler,
        isCancelled: @escaping ConversionCancellationHandler
    ) async throws -> URL
}

public enum ConversionExecutionError: Error, Equatable, Sendable {
    case backendUnavailable(ConversionBackend)
    case backendRejected(ConversionBackend)
}

/// Koordinator portable yang tidak mengetahui UI atau API media platform.
public actor ConversionCoordinator {
    private let capabilities: EngineCapabilities
    private let adapters: [any ConversionBackendAdapter]

    public init(capabilities: EngineCapabilities, adapters: [any ConversionBackendAdapter]) {
        self.capabilities = capabilities
        self.adapters = adapters
    }

    public func execute(
        _ request: ConversionRequest,
        progress: @escaping ConversionProgressHandler = { _ in },
        isCancelled: @escaping ConversionCancellationHandler = { false }
    ) async throws -> URL {
        let plan = try ConversionPlanner.plan(request, capabilities: capabilities)
        guard let adapter = adapters.first(where: { $0.backend == plan.backend }) else {
            throw ConversionExecutionError.backendUnavailable(plan.backend)
        }
        guard adapter.supports(request) else {
            throw ConversionExecutionError.backendRejected(plan.backend)
        }
        return try await adapter.convert(request, progress: progress, isCancelled: isCancelled)
    }
}
