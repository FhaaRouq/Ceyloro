import Foundation

public struct VideoConversionPolicy: Sendable {
    public static let nativeTargets: [TargetFormat] = [.mp4, .mov]

    public init() {}

    public func targets(for source: FileFormat) -> [TargetFormat] {
        guard source.kind == .video else { return [] }
        return Self.nativeTargets.filter { $0.fileExtension != source.fileExtension }
    }
}
