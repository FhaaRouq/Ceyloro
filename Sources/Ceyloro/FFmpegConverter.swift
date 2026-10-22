import AVFoundation
import CeyloroCore
import Foundation

final class FFmpegConverter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func supportedTargets(for files: [URL], candidates: [TargetFormat], ffmpegURL: URL?, encoders: Set<String> = []) -> [TargetFormat] {
        guard let ffmpegURL, isExecutableFile(ffmpegURL), !files.isEmpty else { return [] }
        let formats = files.map(FileFormat.detect(url:))
        let isGIFSelection = formats.allSatisfy { $0.fileExtension == "gif" }
        guard isGIFSelection || formats.allSatisfy({ $0.kind == .audio || $0.kind == .video }) else { return [] }
        let available = candidates.filter { FFmpegConversionPolicy.supports(target: $0, encoders: encoders) }
        if isGIFSelection {
            return available.filter { FFmpegConversionPolicy.videoTargets.contains($0) && $0.fileExtension != "gif" }
        }
        let policy = FFmpegConversionPolicy()
        guard let first = formats.first else { return [] }
        return available.filter { policy.targets(for: first).contains($0) }
    }

    func convert(input: URL, target: TargetFormat, temporaryDirectory: URL, ffmpegURL: URL?, encoders: Set<String> = [], progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool, allowSameFormat: Bool = false, compression: CompressionPreset? = nil) throws -> ConversionResult {
        guard let ffmpegURL, isExecutableFile(ffmpegURL) else { throw ConversionError.ffmpegUnavailable }
        guard FFmpegConversionPolicy.supports(target: target, encoders: encoders) else {
            throw ConversionError.ffmpegFailed(reason: "Binary FFmpeg tidak mendukung encoder untuk format \(target.fileExtension).")
        }
        let source = FileFormat.detect(url: input)
        let allowedTargets = source.fileExtension == "gif"
            ? FFmpegConversionPolicy.videoTargets
            : FFmpegConversionPolicy().targets(for: source)
        guard (allowedTargets.contains(target) || (allowSameFormat && target.fileExtension == source.fileExtension)), fileManager.isReadableFile(atPath: input.path) else {
            throw ConversionError.unsupportedConversion
        }
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let output = temporaryDirectory.appendingPathComponent("output.\(target.fileExtension)")
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = FFmpegCommandBuilder.arguments(input: input, output: output, target: target, encoders: encoders, compression: compression)
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
        let errorQueue = DispatchQueue(label: "com.node.ceyloro.ffmpeg-error")
        var errorBuffer = ""
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else { return }
            errorQueue.sync {
                errorBuffer += text
                if errorBuffer.count > 16384 {
                    errorBuffer = String(errorBuffer.suffix(16384))
                }
            }
        }
        defer {
            progressPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
        }
        while process.isRunning {
            if isCancelled() {
                process.terminate()
                process.waitUntilExit()
                _ = progressPipe.fileHandleForReading.readDataToEndOfFile()
                _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
                try? fileManager.removeItem(at: output)
                throw CancellationError()
            }
            progress(progressQueue.sync { latestProgress })
            Thread.sleep(forTimeInterval: 0.1)
        }
        _ = progressPipe.fileHandleForReading.readDataToEndOfFile()
        let remainingError = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: remainingError, encoding: .utf8) ?? String(data: remainingError, encoding: .ascii), !text.isEmpty {
            errorQueue.sync {
                errorBuffer += text
                if errorBuffer.count > 16384 {
                    errorBuffer = String(errorBuffer.suffix(16384))
                }
            }
        }
        guard process.terminationStatus == 0,
              fileManager.fileExists(atPath: output.path) else {
            try? fileManager.removeItem(at: output)
            let rawError = errorQueue.sync { errorBuffer }
            let reason = Self.extractDiagnosticReason(from: rawError)
            throw ConversionError.ffmpegFailed(reason: reason)
        }
        progress(1)
        return .files([output])
    }

    static func extractDiagnosticReason(from stderr: String) -> String? {
        let lines = stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty &&
                !line.hasPrefix("ffmpeg version") &&
                !line.hasPrefix("built with") &&
                !line.hasPrefix("configuration:") &&
                !line.hasPrefix("libav") &&
                !line.hasPrefix("libsw") &&
                !line.hasPrefix("libpostproc")
            }
        guard !lines.isEmpty else { return nil }
        if let errorLine = lines.last(where: {
            let lower = $0.lowercased()
            return lower.contains("error") || lower.contains("failed") || lower.contains("invalid") || lower.contains("not found")
        }) {
            return String(errorLine.prefix(250))
        }
        return String(lines.last!.prefix(250))
    }

    private func isExecutableFile(_ url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular else { return false }
        return fileManager.isExecutableFile(atPath: url.path)
    }
}
