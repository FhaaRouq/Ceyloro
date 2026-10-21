import Foundation

public struct ArchiveConversionPolicy: Sendable {
    public static let nativeTargets: [TargetFormat] = [.zip, .tar, .gzip]
    public static let nativeSources = ["zip", "tar", "gz", "gzip", "tgz"]
    public static let unsupportedSources = ["rar", "7z"]

    public init() {}

    public func isSupported(source: FileFormat) -> Bool {
        source.kind == .archive && Self.nativeSources.contains(source.fileExtension)
    }

    public func targets(for source: FileFormat) -> [TargetFormat] {
        guard isSupported(source: source) else { return [] }
        return Self.nativeTargets.filter { $0.fileExtension != source.fileExtension }
    }
}
