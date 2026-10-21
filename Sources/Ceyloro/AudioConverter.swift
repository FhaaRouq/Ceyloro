import AVFoundation
import CeyloroCore
import Foundation

final class AudioConverter {
    private struct ExportPlan {
        let presetName: String?
        let fileType: AVFileType
        let pcmSettings: [String: Any]?
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
        let output = temporaryDirectory.appendingPathComponent("output.\(target.fileExtension)")
        let asset = AVURLAsset(url: input)
        if let pcmSettings = plan.pcmSettings {
            return try convertPCM(asset: asset, target: target, output: output, settings: pcmSettings, progress: progress, isCancelled: isCancelled)
        }
        guard let presetName = plan.presetName,
              let session = AVAssetExportSession(asset: asset, presetName: presetName),
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

        var lastProgress = 0.0
        while completion.wait(timeout: .now() + 0.05) == .timedOut {
            if isCancelled() {
                session.cancelExport()
                completion.wait()
                try? FileManager.default.removeItem(at: output)
                throw CancellationError()
            }
            let raw = min(max(Double(session.progress), 0), 0.99)
            lastProgress = max(lastProgress, raw)
            progress(lastProgress)
        }

        if isCancelled() || session.status == .cancelled {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw session.error ?? ConversionError.encodingFailed
        }
        progress(1)
        return .files([output])
    }

    private func canExport(input: URL, plan: ExportPlan) -> Bool {
        if plan.pcmSettings != nil {
            return !AVURLAsset(url: input).tracks(withMediaType: .audio).isEmpty
        }
        let asset = AVURLAsset(url: input)
        guard let presetName = plan.presetName,
              let session = AVAssetExportSession(asset: asset, presetName: presetName) else { return false }
        return session.supportedFileTypes.contains(plan.fileType)
    }

    private func exportPlan(for target: TargetFormat) -> ExportPlan? {
        switch target {
        case .m4a:
            return ExportPlan(presetName: AVAssetExportPresetAppleM4A, fileType: .m4a, pcmSettings: nil)
        case .wav:
            return ExportPlan(presetName: nil, fileType: .wav, pcmSettings: pcmSettings(isBigEndian: false))
        case .aiff:
            return ExportPlan(presetName: nil, fileType: .aiff, pcmSettings: pcmSettings(isBigEndian: true))
        default:
            return nil
        }
    }

    private func pcmSettings(isBigEndian: Bool) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: isBigEndian,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private func convertPCM(asset: AVAsset, target: TargetFormat, output: URL, settings: [String: Any], progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> ConversionResult {
        guard let track = asset.tracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: output, fileType: target == .aiff ? .aiff : .wav) else {
            throw ConversionError.audioEngineUnavailable
        }
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw ConversionError.audioEngineUnavailable }
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw ConversionError.audioEngineUnavailable }
        reader.add(readerOutput)
        writer.add(writerInput)
        guard reader.startReading(), writer.startWriting() else {
            throw reader.error ?? writer.error ?? ConversionError.audioEngineUnavailable
        }
        writer.startSession(atSourceTime: .zero)
        let duration = asset.duration.seconds
        progress(0)

        var lastProgress = 0.0
        let writeQueue = DispatchQueue(label: "ceyloro.audio.pcm.writer", qos: .userInitiated)
        let group = DispatchGroup()
        group.enter()
        var conversionError: Error?
        var hasFinished = false

        writerInput.requestMediaDataWhenReady(on: writeQueue) {
            while writerInput.isReadyForMoreMediaData {
                if hasFinished { return }

                if isCancelled() {
                    hasFinished = true
                    writerInput.markAsFinished()
                    reader.cancelReading()
                    writer.cancelWriting()
                    conversionError = CancellationError()
                    group.leave()
                    return
                }

                if reader.status != .reading {
                    hasFinished = true
                    writerInput.markAsFinished()
                    group.leave()
                    return
                }

                if let sample = readerOutput.copyNextSampleBuffer() {
                    if !writerInput.append(sample) {
                        hasFinished = true
                        writerInput.markAsFinished()
                        writer.cancelWriting()
                        conversionError = writer.error ?? ConversionError.encodingFailed
                        group.leave()
                        return
                    }
                    if duration.isFinite, duration > 0 {
                        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                        let raw = min(max(timestamp / duration, 0), 0.99)
                        lastProgress = max(lastProgress, raw)
                        progress(lastProgress)
                    }
                } else {
                    hasFinished = true
                    writerInput.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
        group.wait()

        if let error = conversionError {
            try? FileManager.default.removeItem(at: output)
            throw error
        }

        guard reader.status == .completed else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw reader.error ?? ConversionError.encodingFailed
        }
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw writer.error ?? ConversionError.encodingFailed
        }
        progress(1)
        return .files([output])
    }
}
