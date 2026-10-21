import Foundation

public struct EngineAvailability: Equatable, Sendable {
    public let avFoundation: Bool
    public let ffmpegURL: URL?

    public init(avFoundation: Bool, ffmpegURL: URL? = nil) {
        self.avFoundation = avFoundation
        self.ffmpegURL = ffmpegURL
    }

    public var hasAudioVideoEngine: Bool {
        avFoundation || ffmpegURL != nil
    }
}

public struct FFmpegLocator {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func locate(customPath: String? = nil, bundleURL: URL? = nil, searchPaths: [URL] = [], environmentPath: String? = nil) -> URL? {
        var candidates: [URL] = []
        if let customPath, !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(URL(fileURLWithPath: customPath))
        }
        if let bundleURL {
            candidates.append(bundleURL.appendingPathComponent("ffmpeg"))
        }
        candidates.append(contentsOf: searchPaths.map { $0.appendingPathComponent("ffmpeg") })
        candidates.append(contentsOf: defaultSearchPaths)
        if let environmentPath {
            candidates.append(contentsOf: environmentPath.split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent("ffmpeg") })
        }

        var seen = Set<URL>()
        for candidate in candidates where seen.insert(candidate.standardizedFileURL).inserted {
            let attributes = try? fileManager.attributesOfItem(atPath: candidate.path)
            let isRegularFile = attributes?[.type] as? FileAttributeType == .typeRegular
            if isRegularFile && fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate.standardizedFileURL
            }
        }
        return nil
    }

    private var defaultSearchPaths: [URL] {
        [
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            URL(fileURLWithPath: "/usr/bin")
        ]
    }
}
