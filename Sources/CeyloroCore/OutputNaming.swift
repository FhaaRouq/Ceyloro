import Foundation

public struct OutputNaming {
    public init() {}

    public func uniqueURL(for input: URL, target: TargetFormat, in directory: URL? = nil, suffix: String = "", fileManager: FileManager = .default) -> URL {
        let folder = directory ?? input.deletingLastPathComponent()
        let base = safeBaseName(input.deletingPathExtension().lastPathComponent)
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
        let safeName = safeBaseName(baseName)
        var candidate = directory.appendingPathComponent(safeName, isDirectory: true)
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(safeName) \(number)", isDirectory: true)
            number += 1
        }
        return candidate
    }

    public func uniqueURL(baseName: String, fileExtension: String, in directory: URL, fileManager: FileManager = .default) -> URL {
        let safeName = safeBaseName(baseName)
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        var candidate = directory.appendingPathComponent("\(safeName).\(normalizedExtension)")
        var number = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(safeName) \(number).\(normalizedExtension)")
            number += 1
        }
        return candidate
    }

    public func pageFileName(baseName: String, index: Int, total: Int, fileExtension: String) -> String {
        let width = max(String(max(total, 1)).count, 2)
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return String(format: "%@-%0*d.%@", safeBaseName(baseName), width, index + 1, normalizedExtension)
    }

    private func safeBaseName(_ value: String) -> String {
        let replaced = value
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .filter { !$0.isNewline }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replaced.isEmpty, replaced != ".", replaced != ".." else { return "Hasil" }
        return replaced
    }
}
