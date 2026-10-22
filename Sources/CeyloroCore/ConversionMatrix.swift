import Foundation

public struct ConversionMatrix: Sendable {
    public init() {}

    public func targets(for source: FileFormat) -> [TargetFormat] {
        switch source.kind {
        case .image:
            return [.jpg, .png, .heic, .tiff, .pdf].filter { $0.fileExtension != source.fileExtension }
        case .pdf:
            return [.jpg, .png, .txt]
        case .audio:
            return [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff].filter { $0.fileExtension != source.fileExtension }
        case .video:
            return ([.mp4, .mov, .mkv, .webm, .avi, .wmv, .gif, .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff]).filter { $0.fileExtension != source.fileExtension }
        case .subtitle:
            return [.srt, .vtt, .txt].filter { $0.fileExtension != source.fileExtension }
        case .archive:
            guard ArchiveConversionPolicy.nativeSources.contains(source.fileExtension) else { return [] }
            return [.zip, .tar, .gzip].filter { $0.fileExtension != source.fileExtension }
        case .document:
            return DocumentConversionPolicy().targets(for: source)
        default:
            return []
        }
    }

    public func commonTargets(for sources: [FileFormat]) -> [TargetFormat] {
        guard let first = sources.first else { return [] }
        return targets(for: first).filter { target in
            sources.dropFirst().allSatisfy { targets(for: $0).contains(target) }
        }
    }
}
