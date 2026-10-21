import Foundation

public struct ArchiveConversionPolicy: Sendable {
    public static let nativeTargets: [TargetFormat] = [.zip, .tar, .gzip]

    public init() {}

    public func targets(for source: FileFormat) -> [TargetFormat] {
        guard source.kind == .archive else { return [] }
        return Self.nativeTargets.filter { $0.fileExtension != source.fileExtension }
    }
}
