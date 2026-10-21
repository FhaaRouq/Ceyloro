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
}

public enum FFmpegCommandBuilder {
    public static func arguments(input: URL, output: URL, target: TargetFormat) -> [String] {
        var arguments = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", input.path]
        switch target {
        case .mp3:
            arguments += ["-vn", "-c:a", "libshine", "-b:a", "192k"]
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
            arguments += ["-c:v", "vp9", "-crf", "32", "-b:v", "0", "-c:a", "opus"]
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
