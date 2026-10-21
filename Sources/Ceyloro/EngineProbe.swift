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
        let encoders = ffmpegURL.map(Self.probeEncoders(at:)) ?? []
        let avFoundation = Self.probeAVFoundation()
        return EngineAvailability(avFoundation: avFoundation, ffmpegURL: ffmpegURL, encoders: encoders)
    }

    static func probeEncoders(at url: URL) -> Set<String> {
        let process = Process()
        process.executableURL = url
        process.arguments = ["-encoders"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
                return []
            }
            var encoders = Set<String>()
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("V") || trimmed.hasPrefix("A") || trimmed.hasPrefix("S") else { continue }
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    encoders.insert(String(parts[1]).lowercased())
                }
            }
            return encoders
        } catch {
            return []
        }
    }

    static func probeAVFoundation() -> Bool {
        !AVAssetExportSession.allExportPresets().isEmpty
    }
}
