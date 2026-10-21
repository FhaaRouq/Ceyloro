import AVFoundation
import CeyloroCore
import Foundation

final class AudioConverter {
    private struct ExportPlan {
        let presetName: String
        let fileType: AVFileType
    }

    func supportedTargets(for files: [URL], candidates: [TargetFormat]) -> [TargetFormat] {
        guard !files.isEmpty,
              files.allSatisfy({ FileFormat.detect(url: $0).kind == .audio }) else { return [] }

        let policy = AudioConversionPolicy()
        return candidates.filter { target in
            guard policy.targets(for: FileFormat.detect(url: files[0])).contains(target),
                  let plan = exportPlan(for: target) else { return false }
            return files.allSatisfy { input in
                canExport(input: input, plan: plan)
            }
        }
    }

    func convert(input: URL, target: TargetFormat, temporaryDirectory: URL, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> ConversionResult {
        guard FileFormat.detect(url: input).kind == .audio,
              AudioConversionPolicy().targets(for: FileFormat.detect(url: input)).contains(target),
              let plan = exportPlan(for: target) else {
            throw ConversionError.unsupportedConversion
        }
        guard FileManager.default.isReadableFile(atPath: input.path) else {
            throw ConversionError.invalidInput
        }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let output = temporaryDirectory.appendingPathComponent("output.(target.fileExtension)")
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: plan.presetName),
              session.supportedFileTypes.contains(plan.fileType) else {
            throw ConversionError.audioEngineUnavailable
        }

        session.outputURL = output
        session.outputFileType = plan.fileType
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

    private func canExport(input: URL, plan: ExportPlan) -> Bool {
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: plan.presetName) else { return false }
        return session.supportedFileTypes.contains(plan.fileType)
    }

    private func exportPlan(for target: TargetFormat) -> ExportPlan? {
        switch target {
        case .m4a:
            return ExportPlan(presetName: AVAssetExportPresetAppleM4A, fileType: .m4a)
        case .wav:
            return ExportPlan(presetName: AVAssetExportPresetPassthrough, fileType: .wav)
        case .aiff:
            return ExportPlan(presetName: AVAssetExportPresetPassthrough, fileType: .aiff)
        default:
            return nil
        }
    }
}
