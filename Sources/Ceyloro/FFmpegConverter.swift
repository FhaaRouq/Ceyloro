import AVFoundation
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
        let isGIFSelection = formats.allSatisfy { $0.fileExtension == "gif" }
        guard isGIFSelection || formats.allSatisfy({ $0.kind == .audio || $0.kind == .video }) else { return [] }
        if isGIFSelection {
            return candidates.filter { FFmpegConversionPolicy.videoTargets.contains($0) && $0.fileExtension != "gif" }
        }
        let policy = FFmpegConversionPolicy()
        guard let first = formats.first else { return [] }
        return candidates.filter { policy.targets(for: first).contains($0) }
    }

    func convert(input: URL, target: TargetFormat, temporaryDirectory: URL, ffmpegURL: URL?, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> ConversionResult {
        guard let ffmpegURL, isExecutableFile(ffmpegURL) else { throw ConversionError.ffmpegUnavailable }
        let source = FileFormat.detect(url: input)
        let allowedTargets = source.fileExtension == "gif"
            ? FFmpegConversionPolicy.videoTargets
            : FFmpegConversionPolicy().targets(for: source)
        guard allowedTargets.contains(target), fileManager.isReadableFile(atPath: input.path) else {
            throw ConversionError.unsupportedConversion
        }
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let output = temporaryDirectory.appendingPathComponent("output.\(target.fileExtension)")
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = FFmpegCommandBuilder.arguments(input: input, output: output, target: target)
        let progressPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = progressPipe
        process.standardError = errorPipe
        try process.run()
        progress(0)
        let duration = AVURLAsset(url: input).duration.seconds
        let progressQueue = DispatchQueue(label: "com.node.ceyloro.ffmpeg-progress")
        var latestProgress = 0.0
        var progressBuffer = ""
        progressPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            progressQueue.sync {
                progressBuffer += text
                let lines = progressBuffer.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
                progressBuffer = progressBuffer.last.map { $0 == "\n" || $0 == "\r" } == true ? "" : String(lines.last ?? "")
                let completeLines = progressBuffer.isEmpty ? lines : lines.dropLast()
                for line in completeLines {
                    let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                    guard parts.count == 2, parts[0] == "out_time_ms", let microseconds = Double(parts[1]), duration.isFinite, duration > 0 else { continue }
                    let value = min(max(microseconds / 1_000_000 / duration, 0), 0.99)
                    latestProgress = max(latestProgress, value)
                }
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        while process.isRunning {
            if isCancelled() {
                progressPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                process.terminate()
                process.waitUntilExit()
                try? fileManager.removeItem(at: output)
                throw CancellationError()
            }
            progress(progressQueue.sync { latestProgress })
            Thread.sleep(forTimeInterval: 0.1)
        }
        progressPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        _ = progressPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
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
