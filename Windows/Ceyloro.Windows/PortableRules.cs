namespace Ceyloro.Windows;

public enum PortableMediaKind
{
    Image,
    Audio,
    Video,
    Pdf,
    Subtitle,
    Archive,
    Unknown
}

public sealed record PortableFileFormat(string Extension, PortableMediaKind Kind)
{
    public static PortableFileFormat Detect(string path)
    {
        var lowerPath = path.ToLowerInvariant();
        var extension = lowerPath.EndsWith(".tar.gz", StringComparison.Ordinal) ? "gzip" : Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
        extension = extension switch
        {
            "jpeg" or "jfif" => "jpg",
            "tif" => "tiff",
            "heif" => "heic",
            "tgz" => "gzip",
            "gz" => "gzip",
            _ => extension
        };

        if (new[] { "jpg", "png", "webp", "heic", "tiff", "bmp", "gif", "avif" }.Contains(extension))
            return new PortableFileFormat(extension, PortableMediaKind.Image);
        if (new[] { "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma" }.Contains(extension))
            return new PortableFileFormat(extension, PortableMediaKind.Audio);
        if (new[] { "mp4", "mov", "mkv", "webm", "avi", "wmv" }.Contains(extension))
            return new PortableFileFormat(extension, PortableMediaKind.Video);
        if (extension == "pdf")
            return new PortableFileFormat(extension, PortableMediaKind.Pdf);
        if (new[] { "srt", "vtt" }.Contains(extension))
            return new PortableFileFormat(extension, PortableMediaKind.Subtitle);
        if (new[] { "zip", "tar", "gzip", "rar", "7z" }.Contains(extension))
            return new PortableFileFormat(extension, PortableMediaKind.Archive);
        return new PortableFileFormat(extension, PortableMediaKind.Unknown);
    }
}

public static class PortablePlanner
{
    private static readonly IReadOnlyDictionary<PortableMediaKind, string[]> targets =
        new Dictionary<PortableMediaKind, string[]>
        {
            [PortableMediaKind.Image] = ["jpg", "png", "heic", "tiff", "pdf"],
            [PortableMediaKind.Pdf] = ["jpg", "png", "txt"],
            [PortableMediaKind.Audio] = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff"],
            [PortableMediaKind.Video] = ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif", "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff"],
            [PortableMediaKind.Subtitle] = ["srt", "vtt", "txt"],
            [PortableMediaKind.Archive] = ["zip", "tar", "gzip"]
        };

    public static IReadOnlyList<string> TargetsFor(IEnumerable<string> paths)
    {
        var formats = paths.Select(PortableFileFormat.Detect).ToArray();
        if (formats.Length == 0 || formats.Any(format => !targets.ContainsKey(format.Kind)))
            return [];

        var common = targets[formats[0].Kind].ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var format in formats.Skip(1))
            common.IntersectWith(targets[format.Kind]);

        foreach (var format in formats)
        {
            if (format.Kind != PortableMediaKind.Pdf)
                common.Remove(format.Extension);
            if (format.Kind == PortableMediaKind.Archive && format.Extension is "rar" or "7z")
                return [];
        }
        return common.OrderBy(value => value).ToArray();
    }
}

