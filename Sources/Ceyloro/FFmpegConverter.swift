import CeyloroCore
import Foundation

final class FFmpegConverter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func supportedTargets(for files: [URL], candidates: [TargetFormat], ffmpegURL: URL?) -> [TargetFormat] {
        guard let ffmpegURL, isExecutableFile(ffmpegURL), !files.isEmpty else { return [] }
        let formats = files.map(FileFormat.detect(url:))
        guard formats.allSatisfy({ $0.kind == .audio || $0.kind == .video }) else { return [] }
        let policy = FFmpegConversionPolicy()
        guard let first = formats.first else { return [] }
        return candidates.filter { policy.targets(for: first).contains($0) }
    }

    func convert(input: URL, target: TargetFormat, temporaryDirectory: URL, ffmpegURL: URL?, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> ConversionResult {
        guard let ffmpegURL, isExecutableFile(ffmpegURL) else { throw ConversionError.ffmpegUnavailable }
        let source = FileFormat.detect(url: input)
        guard FFmpegConversionPolicy().targets(for: source).contains(target), fileManager.isReadableFile(atPath: input.path) else {
            throw ConversionError.unsupportedConversion
        }
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let output = temporaryDirectory.appendingPathComponent("output.\(target.fileExtension)")
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = FFmpegCommandBuilder.arguments(input: input, output: output, target: target)
        let nullOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = nullOutput
        process.standardError = nullOutput
        try process.run()
        progress(0.05)
        var visibleProgress = 0.05
        while process.isRunning {
            if isCancelled() {
                process.terminate()
                process.waitUntilExit()
                try? fileManager.removeItem(at: output)
                throw CancellationError()
            }
            visibleProgress = min(0.95, visibleProgress + 0.02)
            progress(visibleProgress)
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard process.terminationStatus == 0,
              fileManager.fileExists(atPath: output.path) else {
            try? fileManager.removeItem(at: output)
            throw ConversionError.ffmpegFailed
        }
        progress(1)
        return .files([output])
    }

    private func isExecutableFile(_ url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular else { return false }
        return fileManager.isExecutableFile(atPath: url.path)
    }
}
