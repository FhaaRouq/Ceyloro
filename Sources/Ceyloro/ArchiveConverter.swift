import CeyloroCore
import Foundation

final class ArchiveConverter {
    private let fileManager: FileManager
    private let maxExpandedBytes: UInt64 = 2_000_000_000
    // Batas jumlah entri sebelum ekstraksi dimulai — setara dengan implementasi Windows.
    // Mencegah "zip bomb" berupa banyak file kecil yang menghabiskan inode/waktu (temuan B1).
    private let maxEntryCount: Int = 100_000

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func supportedTargets(for files: [URL], candidates: [TargetFormat]) -> [TargetFormat] {
        guard !files.isEmpty,
              files.allSatisfy({ FileFormat.detect(url: $0).kind == .archive && fileManager.isReadableFile(atPath: $0.path) }),
              hasExecutable(at: "/usr/bin/ditto"),
              hasExecutable(at: "/usr/bin/tar") else { return [] }
        let policy = ArchiveConversionPolicy()
        let source = FileFormat.detect(url: files[0])
        guard isSupportedArchive(source, at: files[0]) else { return [] }
        return candidates.filter { policy.targets(for: source).contains($0) }
    }

    func convert(input: URL, target: TargetFormat, temporaryDirectory: URL, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> ConversionResult {
        let source = FileFormat.detect(url: input)
        guard ArchiveConversionPolicy().targets(for: source).contains(target),
              fileManager.isReadableFile(atPath: input.path),
              hasExecutable(at: "/usr/bin/ditto"),
              hasExecutable(at: "/usr/bin/tar"),
              isSupportedArchive(source, at: input) else {
            throw ConversionError.archiveEngineUnavailable
        }
        // Validasi pra-ekstraksi: jumlah entri, path safety (temuan B1).
        // Dilakukan sebelum menyentuh disk agar tidak ada file parsial yang tersisa.
        try validateArchiveEntries(input: input, source: source)
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
            try run(executable: "/usr/bin/ditto", arguments: ["-x", "-k", input.path, destination.path], monitorDirectory: destination, isCancelled: isCancelled)
        case "tar":
            try run(executable: "/usr/bin/tar", arguments: ["-xf", input.path, "-C", destination.path], monitorDirectory: destination, isCancelled: isCancelled)
        case "gz", "gzip", "tgz":
            try run(executable: "/usr/bin/tar", arguments: ["-xzf", input.path, "-C", destination.path], monitorDirectory: destination, isCancelled: isCancelled)
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

    private func run(executable: String, arguments: [String], monitorDirectory: URL? = nil, isCancelled: @escaping () -> Bool) throws {
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
            if let monitorDirectory, expandedSize(of: monitorDirectory) > maxExpandedBytes {
                process.terminate()
                process.waitUntilExit()
                throw ConversionError.archiveTooLarge
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

    /// Validasi entri arsip sebelum ekstraksi:
    /// - Jumlah entri tidak melebihi maxEntryCount
    /// - Tidak ada path yang mengandung path traversal ("../") atau absolute path
    private func validateArchiveEntries(input: URL, source: FileFormat) throws {
        let isTar = ["tar", "gz", "gzip", "tgz"].contains(source.fileExtension)
        let executable = isTar ? "/usr/bin/tar" : "/usr/bin/unzip"
        let args: [String] = isTar
            ? (source.fileExtension == "tar" ? ["-tf", input.path] : ["-tzf", input.path])
            : ["-Z1", input.path]

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        try process.run()

        var entryCount = 0
        var lineBuffer = ""
        let handle = pipe.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty {
                if !process.isRunning { break }
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }
            guard let text = String(data: chunk, encoding: .utf8) else { continue }
            lineBuffer += text
            while let newlineRange = lineBuffer.range(of: "\n") {
                let line = String(lineBuffer[lineBuffer.startIndex..<newlineRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                lineBuffer = String(lineBuffer[newlineRange.upperBound...])
                guard !line.isEmpty else { continue }
                entryCount += 1
                if entryCount > maxEntryCount {
                    process.terminate()
                    process.waitUntilExit()
                    throw ConversionError.archiveTooManyEntries
                }
                if line.hasPrefix("/") || line.contains("../") || line.contains("/..") {
                    process.terminate()
                    process.waitUntilExit()
                    throw ConversionError.archiveUnsafePath
                }
            }
        }
        process.waitUntilExit()
    }

    private func isSupportedArchive(_ source: FileFormat, at url: URL) -> Bool {
        guard ["gz", "gzip", "tgz"].contains(source.fileExtension) else { return true }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tzf", url.path]
        let nullOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = nullOutput
        process.standardError = nullOutput
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func expandedSize(of directory: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        // Tidak menggunakan .skipsHiddenFiles — dotfiles harus dihitung dalam batas ukuran
        // agar arsip berisi banyak file tersembunyi tidak mem-bypass limit 2 GB (temuan B1).
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: Array(keys), options: [])
        var total: UInt64 = 0
        while let url = enumerator?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory != true else { continue }
            total += UInt64(max(values.fileSize ?? 0, 0))
            if total > maxExpandedBytes { return total }
        }
        return total
    }
}
