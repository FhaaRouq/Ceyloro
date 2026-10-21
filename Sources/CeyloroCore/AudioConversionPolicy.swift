import Foundation

public struct AudioConversionPolicy: Sendable {
    public static let nativeTargets: [TargetFormat] = [.m4a, .wav, .aiff]

    public init() {}

    public func targets(for source: FileFormat) -> [TargetFormat] {
        guard source.kind == .audio else { return [] }
        return Self.nativeTargets.filter { $0.fileExtension != source.fileExtension }
    }
}
