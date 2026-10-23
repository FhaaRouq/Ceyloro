import Foundation

public struct EngineAvailability: Equatable, Sendable {
    public let avFoundation: Bool
    public let ffmpegURL: URL?
    public let probeResult: ProbeResult
    public let libreOfficeURL: URL?
    public let pandocURL: URL?

    public init(avFoundation: Bool, ffmpegURL: URL? = nil, probeResult: ProbeResult = .unknown, libreOfficeURL: URL? = nil, pandocURL: URL? = nil) {
        self.avFoundation = avFoundation
        self.ffmpegURL = ffmpegURL
        self.probeResult = probeResult
        self.libreOfficeURL = libreOfficeURL
        self.pandocURL = pandocURL
    }

    /// Encoder set dari probe; kosong jika probe gagal atau belum dijalankan.
    public var encoders: Set<String> {
        probeResult.encoders
    }

    public var hasAudioVideoEngine: Bool {
        avFoundation || ffmpegURL != nil
    }

    public var hasDocumentEngine: Bool {
        libreOfficeURL != nil || pandocURL != nil
    }

    public func hasEncoder(_ name: String) -> Bool {
        encoders.contains(name.lowercased())
    }
}

public struct DocumentEngineLocator {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func locateLibreOffice(customPath: String? = nil, searchPaths: [URL] = [], environmentPath: String? = nil) -> URL? {
        locate(executableName: "soffice", customPath: customPath, searchPaths: searchPaths, environmentPath: environmentPath, defaults: [
            "/Applications/LibreOffice.app/Contents/MacOS",
            "/Applications/LibreOffice.app/Contents/MacOS",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ])
    }

    public func locatePandoc(customPath: String? = nil, searchPaths: [URL] = [], environmentPath: String? = nil) -> URL? {
        locate(executableName: "pandoc", customPath: customPath, searchPaths: searchPaths, environmentPath: environmentPath, defaults: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin"
        ])
    }

    private func locate(executableName: String, customPath: String?, searchPaths: [URL], environmentPath: String?, defaults: [String]) -> URL? {
        var candidates: [URL] = []
        if let customPath, !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(URL(fileURLWithPath: customPath))
        }
        candidates.append(contentsOf: searchPaths.map { $0.appendingPathComponent(executableName) })
        candidates.append(contentsOf: defaults.map { URL(fileURLWithPath: $0).appendingPathComponent(executableName) })
        if let environmentPath {
            candidates.append(contentsOf: environmentPath.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent(executableName)
            })
        }

        var seen = Set<URL>()
        for candidate in candidates where seen.insert(candidate.standardizedFileURL).inserted {
            guard let attributes = try? fileManager.attributesOfItem(atPath: candidate.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  fileManager.isExecutableFile(atPath: candidate.path) else { continue }
            return candidate.standardizedFileURL
        }
        return nil
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
