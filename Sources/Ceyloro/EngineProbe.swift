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
        let executableDirectory = bundle.executableURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? FileManager.default.currentDirectoryPath).deletingLastPathComponent()
        var searchPaths: [URL] = [executableDirectory]
        if let resourceURL = bundle.resourceURL {
            searchPaths.append(resourceURL)
        }
        searchPaths.append(executableDirectory.appendingPathComponent("../Resources").standardizedFileURL)
        searchPaths.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/Ceyloro/Resources"))
        let ffmpegURL = locator.locate(
            customPath: customFFmpegPath,
            bundleURL: bundledURL?.deletingLastPathComponent(),
            searchPaths: searchPaths,
            environmentPath: environment["PATH"]
        )
        _ = AVAsset.self
        return EngineAvailability(avFoundation: true, ffmpegURL: ffmpegURL)
    }
}
