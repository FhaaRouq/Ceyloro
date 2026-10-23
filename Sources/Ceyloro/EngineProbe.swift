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
            searchPaths.append(resourceURL.appendingPathComponent("DocumentEngines/LibreOffice.app/Contents/MacOS"))
            searchPaths.append(resourceURL.appendingPathComponent("DocumentEngines/LibreOffice/Contents/MacOS"))
            searchPaths.append(resourceURL.appendingPathComponent("DocumentEngines/pandoc"))
        }
        searchPaths.append(executableDirectory.appendingPathComponent("../Resources").standardizedFileURL)
        searchPaths.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/Ceyloro/Resources"))
        let ffmpegURL = locator.locate(
            customPath: customFFmpegPath,
            bundleURL: bundledURL?.deletingLastPathComponent(),
            searchPaths: searchPaths,
            environmentPath: environment["PATH"]
        )
        let probeResult = ffmpegURL.map(Self.probeEncoders(at:)) ?? .unknown
        let avFoundation = Self.probeAVFoundation()
        let documentLocator = DocumentEngineLocator()
        let libreOfficeURL = documentLocator.locateLibreOffice(customPath: UserDefaults.standard.string(forKey: "libreOfficePath"), searchPaths: searchPaths, environmentPath: environment["PATH"])
        let pandocURL = documentLocator.locatePandoc(customPath: UserDefaults.standard.string(forKey: "pandocPath"), searchPaths: searchPaths, environmentPath: environment["PATH"])
        return EngineAvailability(avFoundation: avFoundation, ffmpegURL: ffmpegURL, probeResult: probeResult, libreOfficeURL: libreOfficeURL, pandocURL: pandocURL)
    }

    static func probeEncoders(at url: URL) -> ProbeResult {
        let process = Process()
        process.executableURL = url
        process.arguments = ["-encoders"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        // Redirect stderr ke nullDevice — sebelum fix, Pipe() yang tidak pernah dibaca
        // dapat menyebabkan deadlock jika output stderr besar (B4).
        process.standardError = FileHandle.nullDevice

        // Drain stdout secara konkuren menggunakan readabilityHandler (B4).
        let outputQueue = DispatchQueue(label: "com.node.ceyloro.probe-stdout")
        var outputBuffer = Data()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputQueue.sync { outputBuffer.append(data) }
        }

        do {
            try process.run()
            process.waitUntilExit()
            outputPipe.fileHandleForReading.readabilityHandler = nil
            let remaining = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputQueue.sync { outputBuffer.append(remaining) }

            guard process.terminationStatus == 0, let text = String(data: outputBuffer, encoding: .utf8) else {
                return .failed
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
            return .success(encoders: encoders)
        } catch {
            return .failed
        }
    }

    static func probeAVFoundation() -> Bool {
        !AVAssetExportSession.allExportPresets().isEmpty
    }
}
