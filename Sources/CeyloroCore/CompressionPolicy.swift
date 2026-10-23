import Foundation

public enum CompressionPreset: String, Codable, CaseIterable, Sendable {
    case balanced
    case smaller

    public var title: String {
        switch self {
        case .balanced: return "Seimbang"
        case .smaller: return "Lebih kecil"
        }
    }
}

public enum CompressionKind: String, Codable, CaseIterable, Sendable {
    case image
    case audio
    case video
    case pdf
    case document
}

public struct CompressionPlan: Equatable, Sendable {
    public let kind: CompressionKind
    public let outputExtension: String
    public let preservesSourceFormat: Bool

    public init(kind: CompressionKind, outputExtension: String, preservesSourceFormat: Bool) {
        self.kind = kind
        self.outputExtension = outputExtension
        self.preservesSourceFormat = preservesSourceFormat
    }
}

public enum CompressionPolicy {
    public static func plan(for format: FileFormat) -> CompressionPlan? {
        switch format.kind {
        case .image:
            guard ["jpg", "png", "heic", "tiff"].contains(format.fileExtension) else { return nil }
            return CompressionPlan(kind: .image, outputExtension: format.fileExtension, preservesSourceFormat: true)
        case .audio:
            guard ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff"].contains(format.fileExtension) else { return nil }
            return CompressionPlan(kind: .audio, outputExtension: format.fileExtension, preservesSourceFormat: true)
        case .video:
            guard ["mp4", "mov", "mkv", "webm", "avi", "wmv"].contains(format.fileExtension) else { return nil }
            return CompressionPlan(kind: .video, outputExtension: format.fileExtension, preservesSourceFormat: true)
        case .pdf:
            return CompressionPlan(kind: .pdf, outputExtension: "pdf", preservesSourceFormat: true)
        case .document:
            guard ["docx", "xlsx", "pptx"].contains(format.fileExtension) else { return nil }
            return CompressionPlan(kind: .document, outputExtension: format.fileExtension, preservesSourceFormat: true)
        case .subtitle, .archive, .unknown:
            return nil
        }
    }

    public static func commonPlan(for formats: [FileFormat]) -> CompressionPlan? {
        guard let first = formats.first, let firstPlan = plan(for: first) else { return nil }
        guard formats.dropFirst().allSatisfy({
            guard let plan = plan(for: $0) else { return false }
            return plan.kind == firstPlan.kind && plan.outputExtension == firstPlan.outputExtension
        }) else { return nil }
        return firstPlan
    }
}
