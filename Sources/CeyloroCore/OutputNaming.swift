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

    public func uniqueFolderURL(baseName: String, in directory: URL, fileManager: FileManager = .default) -> URL {
        var candidate = directory.appendingPathComponent(baseName, isDirectory: true)
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(number)", isDirectory: true)
            number += 1
        }
        return candidate
    }

    public func uniqueURL(baseName: String, fileExtension: String, in directory: URL, fileManager: FileManager = .default) -> URL {
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        var candidate = directory.appendingPathComponent("\(baseName).\(normalizedExtension)")
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(number).\(normalizedExtension)")
            number += 1
        }
        return candidate
    }

    public func pageFileName(baseName: String, index: Int, total: Int, fileExtension: String) -> String {
        let width = max(String(max(total, 1)).count, 2)
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return String(format: "%@-%0*d.%@", baseName, width, index + 1, normalizedExtension)
    }
}
