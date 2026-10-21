import AVFoundation
import CeyloroCore
import Foundation

final class VideoConverter {
    func supportedTargets(for files: [URL], candidates: [TargetFormat]) -> [TargetFormat] {
        guard !files.isEmpty,
              files.allSatisfy({ FileFormat.detect(url: $0).kind == .video }) else { return [] }

        let policy = VideoConversionPolicy()
        return candidates.filter { target in
            guard policy.targets(for: FileFormat.detect(url: files[0])).contains(target) else { return false }
            return files.allSatisfy { input in
                canExport(input: input, target: target)
            }
        }
    }

    func convert(input: URL, target: TargetFormat, temporaryDirectory: URL, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> ConversionResult {
        guard FileFormat.detect(url: input).kind == .video,
              VideoConversionPolicy().targets(for: FileFormat.detect(url: input)).contains(target) else {
            throw ConversionError.unsupportedConversion
        }
        guard FileManager.default.isReadableFile(atPath: input.path) else {
            throw ConversionError.invalidInput
        }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let output = temporaryDirectory.appendingPathComponent("output.(target.fileExtension)")
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
              let fileType = fileType(for: target),
              session.supportedFileTypes.contains(fileType) else {
            throw ConversionError.videoEngineUnavailable
        }

        session.outputURL = output
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = false
        progress(0)

        let completion = DispatchSemaphore(value: 0)
        session.exportAsynchronously {
            completion.signal()
        }

        while completion.wait(timeout: .now() + 0.05) == .timedOut {
            if isCancelled() {
                session.cancelExport()
                completion.wait()
                throw CancellationError()
            }
            progress(Double(session.progress))
        }

        if isCancelled() || session.status == .cancelled {
            throw CancellationError()
        }
        guard session.status == .completed else {
            throw session.error ?? ConversionError.encodingFailed
        }
        progress(1)
        return .files([output])
    }

    private func canExport(input: URL, target: TargetFormat) -> Bool {
        guard let fileType = fileType(for: target) else { return false }
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return false }
        return session.supportedFileTypes.contains(fileType)
    }

    private func fileType(for target: TargetFormat) -> AVFileType? {
        switch target {
        case .mp4: return .mp4
        case .mov: return .mov
        default: return nil
        }
    }
}
