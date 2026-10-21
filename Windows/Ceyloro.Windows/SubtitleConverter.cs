using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Ceyloro.Windows;

internal static partial class SubtitleConverter
{
    private sealed record Cue(long Start, long End, string Text, string Settings);

    [GeneratedRegex(@"^(?:(\d{1,}):)?(\d{2}):(\d{2})[,.](\d{1,3})$")]
    private static partial Regex TimestampPattern();

    public static string Convert(string input, string target, CancellationToken cancellationToken, Action<double> progress)
    {
        var source = PortableFileFormat.Detect(input).Extension;
        if (source is not ("srt" or "vtt") || target is not ("srt" or "vtt" or "txt"))
            throw new InvalidOperationException("Format subtitle ini tidak didukung.");
        cancellationToken.ThrowIfCancellationRequested();
        var text = ReadText(input);
        progress(0.25);
        var cues = Parse(text, source);
        cancellationToken.ThrowIfCancellationRequested();
        var result = target switch
        {
            "txt" => string.Join(Environment.NewLine, cues.Select(cue => cue.Text)) + Environment.NewLine,
            "srt" => string.Join(Environment.NewLine + Environment.NewLine, cues.Select((cue, index) =>
                $"{index + 1}{Environment.NewLine}{FormatTimestamp(cue.Start, ',')} --> {FormatTimestamp(cue.End, ',')}{Environment.NewLine}{cue.Text}")) + Environment.NewLine,
            _ => "WEBVTT" + Environment.NewLine + Environment.NewLine + string.Join(Environment.NewLine + Environment.NewLine, cues.Select(cue =>
                $"{FormatTimestamp(cue.Start, '.') } --> {FormatTimestamp(cue.End, '.')}{(cue.Settings.Length == 0 ? "" : " " + cue.Settings)}{Environment.NewLine}{cue.Text}")) + Environment.NewLine
        };
        progress(0.9);
        return result;
    }

    public static void Write(string output, string text)
    {
        var temporary = output + ".ceyloro-partial";
        try
        {
            File.WriteAllText(temporary, text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            File.Move(temporary, output);
        }
        finally
        {
            TryDelete(temporary);
        }
    }

    private static string ReadText(string input)
    {
        var bytes = File.ReadAllBytes(input);
        if (bytes.Length == 0)
            throw new InvalidDataException("File subtitle kosong.");
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        if (bytes.AsSpan().StartsWith([0xEF, 0xBB, 0xBF]))
            return Encoding.UTF8.GetString(bytes, 3, bytes.Length - 3);
        if (bytes.AsSpan().StartsWith([0xFF, 0xFE]))
            return Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2);
        if (bytes.AsSpan().StartsWith([0xFE, 0xFF]))
            return Encoding.BigEndianUnicode.GetString(bytes, 2, bytes.Length - 2);
        try
        {
            return new UTF8Encoding(false, true).GetString(bytes);
        }
        catch (DecoderFallbackException)
        {
            return Encoding.GetEncoding(1252).GetString(bytes);
        }
    }

    private static List<Cue> Parse(string text, string format)
    {
        var lines = text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n').Split('\n');
        var cursor = 0;
        if (format == "vtt")
        {
            while (cursor < lines.Length && string.IsNullOrWhiteSpace(lines[cursor])) cursor++;
            if (cursor >= lines.Length || !(lines[cursor].Trim() == "WEBVTT" || lines[cursor].TrimStart().StartsWith("WEBVTT ", StringComparison.Ordinal)))
                throw new InvalidDataException("Header WEBVTT tidak valid.");
            cursor++;
            while (cursor < lines.Length && !string.IsNullOrWhiteSpace(lines[cursor])) cursor++;
        }

        var cues = new List<Cue>();
        while (cursor < lines.Length)
        {
            while (cursor < lines.Length && string.IsNullOrWhiteSpace(lines[cursor])) cursor++;
            if (cursor >= lines.Length) break;
            if (format == "vtt" && (lines[cursor].StartsWith("NOTE", StringComparison.Ordinal) || lines[cursor] is "STYLE" or "REGION"))
            {
                while (cursor < lines.Length && !string.IsNullOrWhiteSpace(lines[cursor])) cursor++;
                continue;
            }
            while (cursor < lines.Length && !lines[cursor].Contains("-->", StringComparison.Ordinal)) cursor++;
            if (cursor >= lines.Length) throw new InvalidDataException("Baris waktu subtitle tidak ditemukan.");
            var parts = lines[cursor++].Split("-->", 2, StringSplitOptions.TrimEntries);
            if (parts.Length != 2) throw new InvalidDataException("Baris waktu subtitle tidak valid.");
            var right = parts[1].Split((char[]?)null, 2, StringSplitOptions.RemoveEmptyEntries);
            if (right.Length == 0) throw new InvalidDataException("Waktu akhir subtitle tidak valid.");
            var start = ParseTimestamp(parts[0]);
            var end = ParseTimestamp(right[0]);
            if (end < start) throw new InvalidDataException("Waktu akhir subtitle lebih awal dari waktu mulai.");
            var content = new List<string>();
            while (cursor < lines.Length && !string.IsNullOrWhiteSpace(lines[cursor])) content.Add(lines[cursor++]);
            if (content.Count == 0) throw new InvalidDataException("Teks subtitle kosong.");
            cues.Add(new Cue(start, end, string.Join(Environment.NewLine, content), right.Length > 1 ? right[1] : string.Empty));
        }
        if (cues.Count == 0) throw new InvalidDataException("Tidak ada subtitle yang dapat dikonversi.");
        return cues;
    }

    private static long ParseTimestamp(string value)
    {
        var match = TimestampPattern().Match(value.Trim());
        if (!match.Success) throw new InvalidDataException("Format waktu subtitle tidak valid.");
        var hours = match.Groups[1].Success ? long.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture) : 0;
        var minutes = long.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture);
        var seconds = long.Parse(match.Groups[3].Value, CultureInfo.InvariantCulture);
        var fraction = match.Groups[4].Value.PadRight(3, '0')[..3];
        var milliseconds = long.Parse(fraction, CultureInfo.InvariantCulture);
        if (minutes > 59 || seconds > 59) throw new InvalidDataException("Rentang waktu subtitle tidak valid.");
        return checked(hours * 3_600_000 + minutes * 60_000 + seconds * 1_000 + milliseconds);
    }

    private static string FormatTimestamp(long milliseconds, char separator)
    {
        var hours = milliseconds / 3_600_000;
        var minutes = milliseconds / 60_000 % 60;
        var seconds = milliseconds / 1_000 % 60;
        var fraction = milliseconds % 1_000;
        return string.Create(CultureInfo.InvariantCulture, $"{hours:00}:{minutes:00}:{seconds:00}{separator}{fraction:000}");
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch { }
    }
}
