using System.Globalization;

namespace Ceyloro.Windows;

internal static class FfmpegCommandBuilder
{
    internal const string GifFilterGraph = "fps=12,scale=w=min(720\\,iw):h=-2:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=sierra2_4a[v]";
    internal const string InputProtocolWhitelist = "file";

    internal static IReadOnlyList<string> BuildInputArguments(string input) =>
        ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-protocol_whitelist", InputProtocolWhitelist, "-i", input];

    public static IReadOnlyList<string> Build(
        string input,
        string output,
        string target,
        FfmpegCapabilities capabilities,
        AppSettings settings)
    {
        var arguments = new List<string>(BuildInputArguments(input));
        if (target is "jpg" or "png" or "heic" or "tiff")
        {
            arguments.AddRange(["-frames:v", "1", "-an", "-c:v", RequiredEncoder(capabilities, target)]);
            if (target == "jpg")
            {
                var quality = Math.Clamp(settings.JpgQuality, 0.1, 1.0);
                arguments.AddRange(["-q:v", Math.Clamp((int)Math.Round(31 - quality * 29), 2, 31).ToString(CultureInfo.InvariantCulture)]);
        }
            else if (target == "heic")
            {
                var crf = Math.Clamp((int)Math.Round(51 * (1 - settings.HeicQuality)), 0, 51);
                arguments.AddRange(["-crf", crf.ToString(CultureInfo.InvariantCulture), "-tag:v", "hvc1"]);
            }
        }
        else if (target is "mp3" or "m4a" or "wav" or "flac" or "ogg" or "opus" or "aiff")
        {
            arguments.AddRange(["-vn", "-c:a", RequiredEncoder(capabilities, target)]);
            if (target is "mp3" or "m4a") arguments.AddRange(["-b:a", "192k"]);
            if (target == "ogg") arguments.AddRange(["-ac", "2", "-q:a", "5"]);
            if (target == "opus") arguments.AddRange(["-b:a", "128k"]);
        }
        else
        {
            arguments.AddRange(["-c:v", RequiredEncoder(capabilities, target)]);
            if (target == "webm") arguments.AddRange(["-crf", "32", "-b:v", "0"]);
            else if (target is "mp4" or "mov" or "mkv" or "avi") arguments.AddRange(["-q:v", "3"]);
            if (target == "gif")
            {
                arguments.AddRange([
                    "-an",
                    "-filter_complex",
                    GifFilterGraph,
                    "-map", "[v]"
                ]);
            }
            else if (target == "webm")
                arguments.AddRange(["-c:a", capabilities.AudioEncoderFor("opus") ?? "copy"]);
            else if (target == "avi")
                arguments.AddRange(["-c:a", capabilities.AudioEncoderFor("mp3") ?? "copy"]);
            else if (target == "wmv")
                arguments.AddRange(["-c:a", "wmav2"]);
            else
                arguments.AddRange(["-c:a", capabilities.AudioEncoderFor("m4a") ?? "copy"]);
            if (target == "mp4") arguments.AddRange(["-movflags", "+faststart"]);
        }
        arguments.AddRange(["-progress", "pipe:1", "-nostats", output]);
        return arguments;
    }

    private static string RequiredEncoder(FfmpegCapabilities capabilities, string target) =>
        capabilities.EncoderFor(target) ?? throw new InvalidOperationException($"Encoder FFmpeg untuk {target.ToUpperInvariant()} tidak tersedia.");
}

