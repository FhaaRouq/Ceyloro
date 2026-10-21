namespace Ceyloro.Windows;

public enum PortableMediaKind
{
    Image,
    Audio,
    Video,
    Pdf,
    Subtitle,
    Unknown
}

public sealed record PortableFileFormat(string Extension, PortableMediaKind Kind)
{
    public static PortableFileFormat Detect(string path)
    {
        var extension = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
        extension = extension switch
        {
            "jpeg" or "jfif" => "jpg",
            "tif" => "tiff",
            "heif" => "heic",
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
        return new PortableFileFormat(extension, PortableMediaKind.Unknown);
    }
}

public static class PortablePlanner
{
    private static readonly IReadOnlyDictionary<PortableMediaKind, string[]> targets =
        new Dictionary<PortableMediaKind, string[]>
        {
            [PortableMediaKind.Image] = ["jpg", "png", "heic", "tiff", "pdf"],
            [PortableMediaKind.Pdf] = ["jpg", "png"],
            [PortableMediaKind.Audio] = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff"],
            [PortableMediaKind.Video] = ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif"],
            [PortableMediaKind.Subtitle] = ["srt", "vtt"]
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
            common.Remove(format.Extension);
        return common.OrderBy(value => value).ToArray();
    }
}
