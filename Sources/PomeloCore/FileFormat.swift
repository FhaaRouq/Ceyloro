import Foundation

public enum MediaKind: String, Codable, Sendable {
    case image
    case pdf
    case audio
    case video
    case document
    case subtitle
    case archive
    case unknown
}

public struct FileFormat: Hashable, Codable, Sendable {
    public let fileExtension: String
    public let kind: MediaKind

    public init(fileExtension: String, kind: MediaKind) {
        self.fileExtension = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        self.kind = kind
    }

    public static func detect(url: URL) -> FileFormat {
        let ext = url.pathExtension.lowercased()
        let image = ["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "bmp", "gif", "avif"]
        let audio = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
        let video = ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif"]
        let document = ["doc", "docx", "rtf", "txt", "md", "pages", "xls", "xlsx", "ppt", "pptx"]
        let subtitle = ["srt", "vtt"]
        let archive = ["zip", "tar", "gz", "gzip", "rar", "7z"]

        if ext == "pdf" { return FileFormat(fileExtension: ext, kind: .pdf) }
        if image.contains(ext) { return FileFormat(fileExtension: ext, kind: .image) }
        if audio.contains(ext) { return FileFormat(fileExtension: ext, kind: .audio) }
        if video.contains(ext) { return FileFormat(fileExtension: ext, kind: .video) }
        if document.contains(ext) { return FileFormat(fileExtension: ext, kind: .document) }
        if subtitle.contains(ext) { return FileFormat(fileExtension: ext, kind: .subtitle) }
        if archive.contains(ext) { return FileFormat(fileExtension: ext, kind: .archive) }
        return FileFormat(fileExtension: ext, kind: .unknown)
    }
}

public enum TargetFormat: String, CaseIterable, Codable, Sendable {
    case jpg
    case png
    case heic
    case tiff
    case pdf
    case txt

    public var title: String {
        switch self {
        case .jpg: return "JPG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .pdf: return "PDF"
        case .txt: return "TXT"
        }
    }

    public var fileExtension: String { rawValue }
}
