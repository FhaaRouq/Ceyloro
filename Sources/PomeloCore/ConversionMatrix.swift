import Foundation

public struct ConversionMatrix: Sendable {
    public init() {}

    public func targets(for source: FileFormat) -> [TargetFormat] {
        switch source.kind {
        case .image:
            return [.jpg, .png, .heic, .tiff, .pdf].filter { $0.fileExtension != source.fileExtension }
        case .pdf:
            return [.jpg, .png, .txt]
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
