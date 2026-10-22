using System.Diagnostics;
using System.Text;

namespace Ceyloro.Windows;

public sealed record DocumentEngines(string? LibreOfficePath, string? PandocPath)
{
    public bool HasAny => LibreOfficePath is not null || PandocPath is not null;
}

internal static class DocumentEngineLocator
{
    public static DocumentEngines Locate(AppSettings settings)
    {
        var baseDirectory = AppContext.BaseDirectory;
        var libreOffice = FindExecutable(settings.LibreOfficePath, "soffice.exe", [
            Path.Combine(baseDirectory, "DocumentEngines", "LibreOffice", "program"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "LibreOffice", "program"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "LibreOffice", "program")
        ]);
        var pandoc = FindExecutable(settings.PandocPath, "pandoc.exe", [Path.Combine(baseDirectory, "DocumentEngines", "pandoc")]);
        return new DocumentEngines(libreOffice, pandoc);
    }

    private static string? FindExecutable(string configured, string fileName, IReadOnlyList<string> defaultDirectories)
    {
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured))
            return Path.GetFullPath(configured);
        foreach (var directory in defaultDirectories)
        {
            var candidate = Path.Combine(directory, fileName);
            if (File.Exists(candidate)) return candidate;
        }
        var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (var directory in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = Path.Combine(directory, fileName);
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }
}

internal static class DocumentConversion
{
    private static readonly HashSet<string> TextSources = new(StringComparer.OrdinalIgnoreCase) { "md", "html", "txt" };
    private static readonly HashSet<string> LibreOfficeSources = new(StringComparer.OrdinalIgnoreCase) { "doc", "docx", "odt", "rtf", "xls", "xlsx", "ods", "ppt", "pptx", "odp" };

    public static bool CanConvert(PortableFileFormat source, string target, DocumentEngines engines)
    {
        var allowed = source.Extension switch
        {
            "doc" or "odt" or "rtf" => new[] { "pdf", "docx" },
            "docx" => new[] { "pdf", "odt", "rtf", "md", "html", "txt" },
            "xls" or "xlsx" or "ods" or "ppt" or "pptx" or "odp" => new[] { "pdf" },
            "md" or "html" or "txt" => new[] { "docx", "pdf" },
            _ => []
        };
        if (!allowed.Contains(target, StringComparer.OrdinalIgnoreCase)) return false;
        if (target.Equals("pdf", StringComparison.OrdinalIgnoreCase) && TextSources.Contains(source.Extension))
            return engines.PandocPath is not null && engines.LibreOfficePath is not null;
        var targetIsText = target.Equals("md", StringComparison.OrdinalIgnoreCase)
            || target.Equals("html", StringComparison.OrdinalIgnoreCase)
            || target.Equals("txt", StringComparison.OrdinalIgnoreCase);
        var usesPandoc = (source.Extension.Equals("docx", StringComparison.OrdinalIgnoreCase) && targetIsText)
            || (TextSources.Contains(source.Extension) && target.Equals("docx", StringComparison.OrdinalIgnoreCase));
        if (usesPandoc)
            return engines.PandocPath is not null;
        return engines.LibreOfficePath is not null;
    }

    public static async Task<string> ConvertAsync(string input, string target, string output, AppSettings settings, CancellationToken cancellationToken, Action<double> progress)
    {
        var source = PortableFileFormat.Detect(input);
        var engines = DocumentEngineLocator.Locate(settings);
        if (!CanConvert(source, target, engines))
            throw new InvalidOperationException("LibreOffice atau pandoc belum tersedia untuk arah konversi ini.");

        var staging = Path.Combine(Path.GetTempPath(), "Ceyloro", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            var safeInput = Path.Combine(staging, "input." + (string.IsNullOrWhiteSpace(source.Extension) ? "bin" : source.Extension));
            File.Copy(input, safeInput);
            var stagedOutput = Path.Combine(staging, "output." + target);
            if (target.Equals("pdf", StringComparison.OrdinalIgnoreCase) && TextSources.Contains(source.Extension))
            {
                var intermediate = Path.Combine(staging, "intermediate.docx");
                await RunPandocAsync(safeInput, intermediate, source.Extension, "docx", engines.PandocPath!, settings, cancellationToken);
                progress(0.55);
                await RunLibreOfficeAsync(intermediate, stagedOutput, "pdf", engines.LibreOfficePath!, settings, cancellationToken);
            }
            else if (UsesPandoc(source.Extension, target))
            {
                await RunPandocAsync(safeInput, stagedOutput, source.Extension, target, engines.PandocPath!, settings, cancellationToken);
            }
            else
            {
                await RunLibreOfficeAsync(safeInput, stagedOutput, target, engines.LibreOfficePath!, settings, cancellationToken);
            }

            if (!File.Exists(stagedOutput) || new FileInfo(stagedOutput).Length == 0)
                throw new InvalidOperationException("Mesin dokumen selesai tetapi file hasil tidak ditemukan.");
            if (target.Equals("pdf", StringComparison.OrdinalIgnoreCase))
            {
                using var stream = File.OpenRead(stagedOutput);
                var header = new byte[5];
                if (stream.Read(header, 0, header.Length) != header.Length || Encoding.ASCII.GetString(header) != "%PDF-")
                    throw new InvalidDataException("Hasil PDF tidak valid.");
            }
            cancellationToken.ThrowIfCancellationRequested();
            Directory.CreateDirectory(Path.GetDirectoryName(output)!);
            File.Move(stagedOutput, output);
            progress(1);
            return output;
        }
        finally
        {
            try { if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true); }
            catch { }
        }
    }

    private static bool UsesPandoc(string source, string target)
    {
        var targetIsText = target.Equals("md", StringComparison.OrdinalIgnoreCase)
            || target.Equals("html", StringComparison.OrdinalIgnoreCase)
            || target.Equals("txt", StringComparison.OrdinalIgnoreCase);
        return (source.Equals("docx", StringComparison.OrdinalIgnoreCase) && targetIsText)
            || (TextSources.Contains(source) && target.Equals("docx", StringComparison.OrdinalIgnoreCase));
    }

    private static async Task RunLibreOfficeAsync(string input, string output, string target, string executable, AppSettings settings, CancellationToken cancellationToken)
    {
        var profile = Path.Combine(Path.GetDirectoryName(output)!, "lo-profile");
        Directory.CreateDirectory(profile);
        var expected = Path.Combine(Path.GetDirectoryName(output)!, Path.GetFileNameWithoutExtension(input) + "." + target);
        var args = new[] { "--headless", "--nologo", "--nodefault", "--nofirststartwizard", "--nolockcheck", $"-env:UserInstallation={new Uri(profile + Path.DirectorySeparatorChar)}", "--convert-to", target, "--outdir", Path.GetDirectoryName(output)!, input };
        await RunProcessAsync(executable, args, settings.DocumentTimeoutSeconds, cancellationToken);
        if (!File.Exists(expected)) throw new InvalidOperationException("LibreOffice tidak menghasilkan file yang diminta.");
        if (!string.Equals(expected, output, StringComparison.OrdinalIgnoreCase)) File.Move(expected, output, overwrite: true);
    }

    private static Task RunPandocAsync(string input, string output, string source, string target, string executable, AppSettings settings, CancellationToken cancellationToken)
    {
        var from = source switch { "md" => "markdown", "html" => "html", "txt" => "plain", _ => source };
        var to = target switch { "md" => "gfm", "html" => "html", "txt" => "plain", _ => target };
        return RunProcessAsync(executable, ["--from", from, "--to", to, "--output", output, input], settings.DocumentTimeoutSeconds, cancellationToken);
    }

    private static async Task RunProcessAsync(string executable, IEnumerable<string> arguments, int timeoutSeconds, CancellationToken cancellationToken)
    {
        using var process = new Process { StartInfo = new ProcessStartInfo { FileName = executable, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true } };
        foreach (var argument in arguments) process.StartInfo.ArgumentList.Add(argument);
        if (!process.Start()) throw new InvalidOperationException("Mesin dokumen tidak dapat dijalankan.");
        using var registration = cancellationToken.Register(() => { try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { } });
        var errorTask = process.StandardError.ReadToEndAsync();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(Math.Max(timeoutSeconds, 1)));
        try { await process.WaitForExitAsync(timeout.Token); }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
            throw new TimeoutException("Konversi dokumen melewati batas waktu.");
        }
        var error = await errorTask;
        cancellationToken.ThrowIfCancellationRequested();
        if (process.ExitCode != 0) throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? "Mesin dokumen gagal." : error.Trim());
    }
}
