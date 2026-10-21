import CeyloroCore
import Foundation

final class SubtitleConverter {
    func supportedTargets(for files: [URL], candidates: [TargetFormat]) -> [TargetFormat] {
        guard !files.isEmpty,
              files.allSatisfy({ FileFormat.detect(url: $0).kind == .subtitle && FileManager.default.isReadableFile(atPath: $0.path) }) else { return [] }
        let policy = SubtitleConversionPolicy()
        return candidates.filter { policy.targets(for: FileFormat.detect(url: files[0])).contains($0) }
    }

    func convert(input: URL, target: TargetFormat, temporaryDirectory: URL, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> ConversionResult {
        let source = FileFormat.detect(url: input)
        guard let sourceFormat = SubtitleFormat(rawValue: source.fileExtension),
              let targetFormat = SubtitleFormat(rawValue: target.fileExtension),
              SubtitleConversionPolicy().targets(for: source).contains(target),
              FileManager.default.isReadableFile(atPath: input.path) else {
            throw ConversionError.invalidInput
        }
        if isCancelled() { throw CancellationError() }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let text: String
        do {
            text = try String(contentsOf: input, encoding: .utf8)
        } catch {
            throw ConversionError.invalidInput
        }
        progress(0.35)
        if isCancelled() { throw CancellationError() }
        let converted: String
        do {
            converted = try SubtitleTranscoder.convert(text, from: sourceFormat, to: targetFormat)
        } catch {
            throw ConversionError.invalidInput
        }
        let output = temporaryDirectory.appendingPathComponent("output.\(target.fileExtension)")
        do {
            try converted.write(to: output, atomically: true, encoding: .utf8)
        } catch {
            throw ConversionError.encodingFailed
        }
        progress(1)
        return .files([output])
    }
}
