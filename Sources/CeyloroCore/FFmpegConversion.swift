import Foundation

/// Hasil probe encoder FFmpeg.
/// - `.success(encoders:)`: probe berhasil, berisi daftar encoder yang tersedia.
/// - `.failed`: probe dijalankan tapi gagal (FFmpeg error, exit non-zero).
/// - `.unknown`: probe belum dijalankan atau FFmpeg tidak ditemukan.
/// `FFmpegConversionPolicy.supports` mengembalikan `false` untuk `.failed` dan `.unknown`
/// agar target tidak ditawarkan tanpa verifikasi kemampuan (temuan B3).
public enum ProbeResult: Equatable, Sendable {
    case success(encoders: Set<String>)
    case failed
    case unknown

    /// Encoder set dari hasil probe; kosong untuk `.failed`/`.unknown`.
    public var encoders: Set<String> {
        if case .success(let encoders) = self { return encoders }
        return []
    }
}

public struct FFmpegConversionPolicy: Sendable {
    public static let audioTargets: [TargetFormat] = [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff]
    public static let videoTargets: [TargetFormat] = [.mp4, .mov, .mkv, .webm, .avi, .wmv, .gif]

    public init() {}

    public func targets(for source: FileFormat) -> [TargetFormat] {
        switch source.kind {
        case .audio:
            return Self.audioTargets.filter { $0.fileExtension != source.fileExtension }
        case .video:
            return (Self.videoTargets + Self.audioTargets).filter { $0.fileExtension != source.fileExtension }
        default:
            return []
        }
    }

    public static func supports(target: TargetFormat, probe: ProbeResult) -> Bool {
        guard case .success(let encoders) = probe else { return false }
        switch target {
        case .mp3:
            return encoders.contains("libshine") || encoders.contains("libmp3lame") || encoders.contains("mp3")
        case .m4a:
            return encoders.contains("aac") || encoders.contains("libfdk_aac")
        case .wav:
            return encoders.contains("pcm_s16le") || encoders.contains("pcm_s16be")
        case .flac:
            return encoders.contains("flac")
        case .ogg:
            return encoders.contains("vorbis") || encoders.contains("libvorbis")
        case .opus:
            return encoders.contains("opus") || encoders.contains("libopus")
        case .aiff:
            return encoders.contains("pcm_s16be") || encoders.contains("pcm_s16le")
        case .mp4, .mov, .mkv:
            let hasVideo = encoders.contains("h264_videotoolbox") || encoders.contains("libx264") || encoders.contains("h264") || encoders.contains("mpeg4")
            let hasAudio = encoders.contains("aac") || encoders.contains("libfdk_aac") || encoders.contains("pcm_s16le")
            return hasVideo && hasAudio
        case .webm:
            let hasVideo = encoders.contains("vp9") || encoders.contains("libvpx-vp9") || encoders.contains("vp8") || encoders.contains("libvpx")
            let hasAudio = encoders.contains("opus") || encoders.contains("libopus") || encoders.contains("vorbis") || encoders.contains("libvorbis")
            return hasVideo && hasAudio
        case .avi:
            return encoders.contains("mpeg4") || encoders.contains("mjpeg") || encoders.contains("libx264")
        case .wmv:
            return encoders.contains("wmv2") || encoders.contains("wmv1")
        case .gif:
            return encoders.contains("gif")
        default:
            return false
        }
    }
}

public enum FFmpegCommandBuilder {
    private static func videoCodecArgs(encoders: Set<String>, compression: CompressionPreset?) -> (String, [String]) {
        if encoders.contains("h264_videotoolbox") {
            let quality = compression == .smaller ? "50" : "60"
            return ("h264_videotoolbox", ["-q:v", quality])
        } else if encoders.contains("libx264") || encoders.contains("h264") {
            let codec = encoders.contains("libx264") ? "libx264" : "h264"
            let crf = compression == .smaller ? "28" : "23"
            return (codec, ["-crf", crf, "-preset", "medium"])
        } else {
            let qv = compression == .smaller ? "7" : "5"
            return ("mpeg4", ["-q:v", qv])
        }
    }

    public static func arguments(input: URL, output: URL, target: TargetFormat, encoders: Set<String> = [], compression: CompressionPreset? = nil) -> [String] {
        var arguments = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-protocol_whitelist", "file,crypto,data", "-i", input.path]
        switch target {
        case .mp3:
            let codec = encoders.contains("libmp3lame") || encoders.isEmpty ? "libmp3lame" : (encoders.contains("libshine") ? "libshine" : "mp3")
            arguments += ["-vn", "-c:a", codec, "-b:a", compression == nil ? "192k" : compression == .smaller ? "96k" : "128k"]
        case .m4a:
            arguments += ["-vn", "-c:a", "aac", "-b:a", compression == nil ? "192k" : compression == .smaller ? "96k" : "128k"]
        case .wav:
            arguments += ["-vn", "-c:a", "pcm_s16le"]
        case .flac:
            arguments += ["-vn", "-c:a", "flac"]
        case .ogg:
            arguments += ["-vn", "-ac", "2", "-strict", "-2", "-c:a", "vorbis", "-q:a", compression == nil ? "5" : compression == .smaller ? "3" : "4"]
        case .opus:
            arguments += ["-vn", "-strict", "-2", "-c:a", "opus", "-b:a", compression == nil ? "128k" : compression == .smaller ? "64k" : "96k"]
        case .aiff:
            arguments += ["-vn", "-c:a", "pcm_s16be"]
        case .mp4:
            let (vcodec, vargs) = videoCodecArgs(encoders: encoders, compression: compression)
            arguments += ["-c:v", vcodec] + vargs + ["-c:a", "aac", "-movflags", "+faststart"]
        case .mov:
            let (vcodec, vargs) = videoCodecArgs(encoders: encoders, compression: compression)
            arguments += ["-c:v", vcodec] + vargs + ["-c:a", "aac"]
        case .mkv:
            let (vcodec, vargs) = videoCodecArgs(encoders: encoders, compression: compression)
            arguments += ["-c:v", vcodec] + vargs + ["-c:a", "aac"]
        case .webm:
            let videoCodec = encoders.contains("vp9") || encoders.isEmpty ? "vp9" : (encoders.contains("libvpx-vp9") ? "libvpx-vp9" : "vp8")
            arguments += ["-c:v", videoCodec, "-crf", compression == .smaller ? "42" : "36", "-b:v", "0", "-c:a", "opus"]
        case .avi:
            arguments += ["-c:v", "mpeg4", "-q:v", compression == .smaller ? "7" : "5", "-c:a", "mp3"]
        case .wmv:
            arguments += ["-c:v", "wmv2", "-c:a", "wmav2"]
        case .gif:
            arguments += ["-an", "-vf", "fps=12,scale='min(480,iw)':-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"]
        default:
            break
        }
        arguments += ["-progress", "pipe:1", "-nostats"]
        arguments.append(output.path)
        return arguments
    }
}
