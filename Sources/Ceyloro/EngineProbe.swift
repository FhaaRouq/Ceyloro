import AVFoundation
import CeyloroCore
import Foundation

struct RuntimeEngineProbe {
    private let locator: FFmpegLocator

    init(fileManager: FileManager = .default) {
        locator = FFmpegLocator(fileManager: fileManager)
    }

    func inspect(customFFmpegPath: String? = nil, bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> EngineAvailability {
        let bundledURL = bundle.url(forResource: "ffmpeg", withExtension: nil)
        let ffmpegURL = locator.locate(
            customPath: customFFmpegPath,
            bundleURL: bundledURL?.deletingLastPathComponent(),
            environmentPath: environment["PATH"]
        )
        _ = AVAsset.self
        return EngineAvailability(avFoundation: true, ffmpegURL: ffmpegURL)
    }
}
