import Foundation

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

    public static func supports(target: TargetFormat, encoders: Set<String>) -> Bool {
        guard !encoders.isEmpty else { return true }
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
            let hasVideo = encoders.contains("mpeg4") || encoders.contains("libx264") || encoders.contains("h264")
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
    public static func arguments(input: URL, output: URL, target: TargetFormat, encoders: Set<String> = []) -> [String] {
        var arguments = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", input.path]
        switch target {
        case .mp3:
            let codec = encoders.contains("libshine") || encoders.isEmpty ? "libshine" : (encoders.contains("libmp3lame") ? "libmp3lame" : "mp3")
            arguments += ["-vn", "-c:a", codec, "-b:a", "192k"]
        case .m4a:
            arguments += ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case .wav:
            arguments += ["-vn", "-c:a", "pcm_s16le"]
        case .flac:
            arguments += ["-vn", "-c:a", "flac"]
        case .ogg:
            arguments += ["-vn", "-ac", "2", "-strict", "-2", "-c:a", "vorbis", "-q:a", "5"]
        case .opus:
            arguments += ["-vn", "-strict", "-2", "-c:a", "opus", "-b:a", "128k"]
        case .aiff:
            arguments += ["-vn", "-c:a", "pcm_s16be"]
        case .mp4:
            arguments += ["-c:v", "mpeg4", "-q:v", "3", "-c:a", "aac", "-movflags", "+faststart"]
        case .mov:
            arguments += ["-c:v", "mpeg4", "-q:v", "3", "-c:a", "aac"]
        case .mkv:
            arguments += ["-c:v", "mpeg4", "-q:v", "3", "-c:a", "aac"]
        case .webm:
            let videoCodec = encoders.contains("vp9") || encoders.isEmpty ? "vp9" : (encoders.contains("libvpx-vp9") ? "libvpx-vp9" : "vp8")
            arguments += ["-c:v", videoCodec, "-crf", "32", "-b:v", "0", "-c:a", "opus"]
        case .avi:
            arguments += ["-c:v", "mpeg4", "-q:v", "3", "-c:a", "mp3"]
        case .wmv:
            arguments += ["-c:v", "wmv2", "-c:a", "wmav2"]
        case .gif:
            arguments += ["-an", "-vf", "fps=12,scale=iw:-1:flags=lanczos"]
        default:
            break
        }
        arguments += ["-progress", "pipe:1", "-nostats"]
        arguments.append(output.path)
        return arguments
    }
}
