import Foundation
import UniformTypeIdentifiers

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
        let normalized = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch normalized {
        case "jpeg", "jfif": self.fileExtension = "jpg"
        case "tif": self.fileExtension = "tiff"
        case "heif": self.fileExtension = "heic"
        case "tgz": self.fileExtension = "gz"
        default: self.fileExtension = normalized
        }
        self.kind = kind
    }

    public static func detect(url: URL) -> FileFormat {
        let rawExt = url.pathExtension.lowercased()
        let normalized = FileFormat(fileExtension: rawExt, kind: .unknown).fileExtension
        let ext = normalized
        let image = ["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "bmp", "gif", "avif", "jfif"]
        let audio = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
        let video = ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif"]
        let document = ["pdf", "doc", "docx", "odt", "rtf", "txt", "md", "html", "pages", "xls", "xlsx", "ods", "ppt", "pptx", "odp"]
        let subtitle = ["srt", "vtt"]
        let archive = ["zip", "tar", "gz", "gzip", "tgz", "rar", "7z"]

        if ext == "pdf" { return FileFormat(fileExtension: ext, kind: .pdf) }
        if image.contains(ext) || image.contains(rawExt) { return FileFormat(fileExtension: ext, kind: .image) }
        if audio.contains(ext) || audio.contains(rawExt) { return FileFormat(fileExtension: ext, kind: .audio) }
        if video.contains(ext) || video.contains(rawExt) { return FileFormat(fileExtension: ext, kind: .video) }
        if document.contains(ext) || document.contains(rawExt) { return FileFormat(fileExtension: ext, kind: .document) }
        if subtitle.contains(ext) || subtitle.contains(rawExt) { return FileFormat(fileExtension: ext, kind: .subtitle) }
        if archive.contains(ext) || archive.contains(rawExt) { return FileFormat(fileExtension: ext, kind: .archive) }
        if let type = UTType(filenameExtension: rawExt), type.conforms(to: .image) {
            return FileFormat(fileExtension: ext, kind: .image)
        }
        return FileFormat(fileExtension: ext, kind: .unknown)
    }
}

public enum TargetFormat: String, CaseIterable, Codable, Sendable {
    case jpg
    case png
    case heic
    case tiff
    case pdf
    case docx
    case odt
    case rtf
    case md
    case html
    case txt
    case mp3
    case m4a
    case wav
    case flac
    case ogg
    case opus
    case aiff
    case mp4
    case mov
    case mkv
    case webm
    case avi
    case wmv
    case gif
    case srt
    case vtt
    case zip
    case tar
    case gzip

    public var title: String {
        switch self {
        case .jpg: return "JPG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .pdf: return "PDF"
        case .docx: return "DOCX"
        case .odt: return "ODT"
        case .rtf: return "RTF"
        case .md: return "MD"
        case .html: return "HTML"
        case .txt: return "TXT"
        case .mp3: return "MP3"
        case .m4a: return "M4A"
        case .wav: return "WAV"
        case .flac: return "FLAC"
        case .ogg: return "OGG"
        case .opus: return "OPUS"
        case .aiff: return "AIFF"
        case .mp4: return "MP4"
        case .mov: return "MOV"
        case .mkv: return "MKV"
        case .webm: return "WebM"
        case .avi: return "AVI"
        case .wmv: return "WMV"
        case .gif: return "GIF"
        case .srt: return "SRT"
        case .vtt: return "VTT"
        case .zip: return "ZIP"
        case .tar: return "TAR"
        case .gzip: return "GZIP"
        }
    }

    public var fileExtension: String {
        self == .gzip ? "tar.gz" : rawValue
    }
}
