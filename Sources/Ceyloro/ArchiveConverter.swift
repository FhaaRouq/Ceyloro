import CeyloroCore
import Foundation

final class ArchiveConverter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func supportedTargets(for files: [URL], candidates: [TargetFormat]) -> [TargetFormat] {
        guard !files.isEmpty,
              files.allSatisfy({ FileFormat.detect(url: $0).kind == .archive && fileManager.isReadableFile(atPath: $0.path) }),
              hasExecutable(at: "/usr/bin/ditto"),
              hasExecutable(at: "/usr/bin/tar") else { return [] }
        let policy = ArchiveConversionPolicy()
        return candidates.filter { policy.targets(for: FileFormat.detect(url: files[0])).contains($0) }
    }

    func convert(input: URL, target: TargetFormat, temporaryDirectory: URL, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> ConversionResult {
        let source = FileFormat.detect(url: input)
        guard ArchiveConversionPolicy().targets(for: source).contains(target),
              fileManager.isReadableFile(atPath: input.path),
              hasExecutable(at: "/usr/bin/ditto"),
              hasExecutable(at: "/usr/bin/tar") else {
            throw ConversionError.archiveEngineUnavailable
        }
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let staging = temporaryDirectory.appendingPathComponent("archive-staging", isDirectory: true)
        let contentRoot = staging.appendingPathComponent(archiveBaseName(for: input, source: source), isDirectory: true)
        try fileManager.createDirectory(at: contentRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        progress(0.1)
        try extract(input: input, source: source, destination: contentRoot, isCancelled: isCancelled)
        progress(0.55)
        if isCancelled() { throw CancellationError() }

        let output = temporaryDirectory.appendingPathComponent("output.\(target.fileExtension)")
        try create(target: target, contentRoot: contentRoot, output: output, isCancelled: isCancelled)
        progress(1)
        return .files([output])
    }

    private func extract(input: URL, source: FileFormat, destination: URL, isCancelled: @escaping () -> Bool) throws {
        switch source.fileExtension {
        case "zip":
            try run(executable: "/usr/bin/ditto", arguments: ["-x", "-k", input.path, destination.path], isCancelled: isCancelled)
        case "tar":
            try run(executable: "/usr/bin/tar", arguments: ["-xf", input.path, "-C", destination.path], isCancelled: isCancelled)
        case "gz", "gzip", "tgz":
            try run(executable: "/usr/bin/tar", arguments: ["-xzf", input.path, "-C", destination.path], isCancelled: isCancelled)
        default:
            throw ConversionError.unsupportedConversion
        }
    }

    private func create(target: TargetFormat, contentRoot: URL, output: URL, isCancelled: @escaping () -> Bool) throws {
        let packRoot = try preferredPackRoot(for: contentRoot)
        let parent = packRoot.deletingLastPathComponent()
        let name = packRoot.lastPathComponent
        switch target {
        case .zip:
            try run(executable: "/usr/bin/ditto", arguments: ["-c", "-k", "--keepParent", packRoot.path, output.path], isCancelled: isCancelled)
        case .tar:
            try run(executable: "/usr/bin/tar", arguments: ["-cf", output.path, "-C", parent.path, name], isCancelled: isCancelled)
        case .gzip:
            try run(executable: "/usr/bin/tar", arguments: ["-czf", output.path, "-C", parent.path, name], isCancelled: isCancelled)
        default:
            throw ConversionError.unsupportedConversion
        }
    }

    private func preferredPackRoot(for contentRoot: URL) throws -> URL {
        let entries = try fileManager.contentsOfDirectory(at: contentRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        if entries.count == 1, let candidate = entries.first,
           (try candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return candidate
        }
        return contentRoot
    }

    private func archiveBaseName(for input: URL, source: FileFormat) -> String {
        var name = input.deletingPathExtension().lastPathComponent
        if ["gz", "gzip"].contains(source.fileExtension), name.lowercased().hasSuffix(".tar") {
            name = String(name.dropLast(4))
        }
        return name.isEmpty ? "archive" : name
    }

    private func run(executable: String, arguments: [String], isCancelled: @escaping () -> Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        while process.isRunning {
            if isCancelled() {
                process.terminate()
                process.waitUntilExit()
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard process.terminationStatus == 0 else {
            throw ConversionError.archiveConversionFailed
        }
    }

    private func hasExecutable(at path: String) -> Bool {
        fileManager.isExecutableFile(atPath: path)
    }
}
