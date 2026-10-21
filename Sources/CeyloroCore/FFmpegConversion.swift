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
            return Self.videoTargets.filter { $0.fileExtension != source.fileExtension }
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
            arguments += ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case .m4a:
            arguments += ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case .wav:
            arguments += ["-vn", "-c:a", "pcm_s16le"]
        case .flac:
            arguments += ["-vn", "-c:a", "flac"]
        case .ogg:
            arguments += ["-vn", "-c:a", "libvorbis", "-q:a", "5"]
        case .opus:
            arguments += ["-vn", "-c:a", "libopus", "-b:a", "128k"]
        case .aiff:
            arguments += ["-vn", "-c:a", "pcm_s16be"]
        case .mp4:
            arguments += ["-c:v", "libx264", "-preset", "medium", "-crf", "23", "-c:a", "aac", "-movflags", "+faststart"]
        case .mov:
            arguments += ["-c:v", "libx264", "-preset", "medium", "-crf", "23", "-c:a", "aac"]
        case .mkv:
            arguments += ["-c:v", "libx264", "-c:a", "aac"]
        case .webm:
            arguments += ["-c:v", "libvpx-vp9", "-c:a", "libopus"]
        case .avi:
            arguments += ["-c:v", "libx264", "-c:a", "libmp3lame"]
        case .wmv:
            arguments += ["-c:v", "wmv2", "-c:a", "wmav2"]
        case .gif:
            arguments += ["-an", "-vf", "fps=12,scale=iw:-1:flags=lanczos"]
        default:
            break
        }
        arguments.append(output.path)
        return arguments
    }
}
