import Foundation

public struct OutputNaming {
    public init() {}

    public func uniqueURL(for input: URL, target: TargetFormat, in directory: URL? = nil, suffix: String = "", fileManager: FileManager = .default) -> URL {
        let folder = directory ?? input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let cleanSuffix = suffix.isEmpty ? "" : "-\(suffix.trimmingCharacters(in: CharacterSet(charactersIn: "-")))"
        var candidate = folder.appendingPathComponent("\(base)\(cleanSuffix).\(target.fileExtension)")
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)\(cleanSuffix) \(number).\(target.fileExtension)")
            number += 1
        }
        return candidate
    }
}
