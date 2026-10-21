import Foundation

public struct ArchiveConversionPolicy: Sendable {
    public static let nativeTargets: [TargetFormat] = [.zip, .tar, .gzip]
    public static let nativeSources = ["zip", "tar", "gz", "gzip", "tgz"]

    public init() {}

    public func targets(for source: FileFormat) -> [TargetFormat] {
        guard source.kind == .archive, Self.nativeSources.contains(source.fileExtension) else { return [] }
        return Self.nativeTargets.filter { $0.fileExtension != source.fileExtension }
    }
}
