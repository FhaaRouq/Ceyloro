using System.Diagnostics;
using System.Globalization;

namespace Ceyloro.Windows;

public sealed record ConversionFailure(string Input, string Message);
public sealed record BatchResult(IReadOnlyList<string> Outputs, IReadOnlyList<ConversionFailure> Failures);

public sealed class ConversionEngine
{
    private readonly SettingsStore settings;
    private readonly object capabilityGate = new();
    private string? capabilityPath;
    private FfmpegCapabilities? cachedCapabilities;
    private Task<FfmpegCapabilities?>? capabilityTask;

    public ConversionEngine(SettingsStore settings)
    {
        this.settings = settings;
        StartCapabilityProbe();
    }

    public SettingsStore Settings => settings;
    public bool IsCheckingCapabilities => capabilityTask is { IsCompleted: false };

    public IReadOnlyList<string> TargetsFor(IEnumerable<string> paths)
    {
        var files = paths.ToArray();
        var targets = PortablePlanner.TargetsFor(files).ToList();
        if (files.Length == 0) return targets;
        var formats = files.Select(PortableFileFormat.Detect).ToArray();
        if (formats.All(format => format.Kind is PortableMediaKind.Pdf or PortableMediaKind.Subtitle or PortableMediaKind.Archive))
            return targets;

        if (formats.Any(format => format.Kind == PortableMediaKind.Image && !PdfConversion.CanCreatePdfFromImage(format.Extension)))
            targets.Remove("pdf");

        var capabilities = TryGetCapabilities();
        var hasAnimatedGif = formats.All(format => format.Extension == "gif") && files.Any(IsAnimatedGif);
        if (hasAnimatedGif)
        {
            targets.AddRange(["mp4", "mov", "mkv", "webm", "avi", "wmv", "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff"]);
            targets = targets.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        }
        return targets.Where(target =>
        {
            var needsFfmpeg = formats.Any(format =>
                format.Kind is PortableMediaKind.Audio or PortableMediaKind.Video ||
                (format.Kind == PortableMediaKind.Image && target != "pdf"));
            return !needsFfmpeg || capabilities?.Supports(target) == true;
        }).ToArray();
    }

    private static bool IsAnimatedGif(string path)
    {
        try
        {
            using var image = Image.FromFile(path);
            var dimension = new System.Drawing.Imaging.FrameDimension(image.FrameDimensionsList[0]);
            return image.GetFrameCount(dimension) > 1;
        }
        catch { return false; }
    }

    public string EmptyStateFor(IEnumerable<string> paths)
    {
        var files = paths.ToArray();
        if (files.Length == 0) return "File tidak dapat dibaca";
        var formats = files.Select(PortableFileFormat.Detect).ToArray();
        if (formats.Any(format => !Enum.IsDefined(format.Kind) || format.Kind == PortableMediaKind.Unknown))
            return "Format file belum didukung";
        var needsFfmpeg = formats.Any(format => format.Kind is PortableMediaKind.Audio or PortableMediaKind.Video ||
            (format.Kind == PortableMediaKind.Image && format.Extension != "pdf"));
        if (needsFfmpeg && TryGetCapabilities() is null)
            return IsCheckingCapabilities
                ? "Memeriksa FFmpeg…"
                : "FFmpeg tidak ditemukan atau tidak dapat dijalankan";
        return "Format file belum didukung";
    }

    public async Task<BatchResult> ConvertAsync(
        IReadOnlyList<string> inputs,
        string target,
        IProgress<double>? progress,
        CancellationToken cancellationToken,
        PdfConversionOptions? pdfOptions = null,
        Action<string>? currentInputChanged = null)
    {
        var outputs = new List<string>();
        var failures = new List<ConversionFailure>();
        var total = Math.Max(inputs.Count, 1);

        for (var index = 0; index < inputs.Count; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                currentInputChanged?.Invoke(Path.GetFileName(inputs[index]));
                var output = await ConvertOneAsync(inputs[index], target, cancellationToken,
                    value => progress?.Report(value < 0 ? -1 : (index + value) / total), pdfOptions);
                outputs.Add(output);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception error)
            {
                failures.Add(new ConversionFailure(inputs[index], error.Message));
            }
            progress?.Report((index + 1d) / total);
        }

        return new BatchResult(outputs, failures);
    }

    public async Task<string> MergeImagesToPdfAsync(
        IReadOnlyList<string> inputs,
        string outputName,
        PdfConversionOptions options,
        IProgress<double>? progress,
        CancellationToken cancellationToken)
    {
        if (inputs.Count == 0 || inputs.Any(path => PortableFileFormat.Detect(path).Kind != PortableMediaKind.Image))
            throw new InvalidOperationException("Pilih satu atau beberapa gambar untuk membuat PDF.");
        var outputDirectory = ResolveOutputDirectory(inputs[0]);
        Directory.CreateDirectory(outputDirectory);
        var cleanName = Path.GetFileNameWithoutExtension(outputName.Trim());
        if (string.IsNullOrWhiteSpace(cleanName)) cleanName = "Gabungan";
        var output = UniqueOutputPath(outputDirectory, cleanName, "pdf");
        await Task.Run(() => PdfConversion.CreateImagePdf(inputs, output, options, cancellationToken, value => progress?.Report(value)), cancellationToken);
        return output;
    }

    private async Task<string> ConvertOneAsync(
        string input,
        string target,
        CancellationToken cancellationToken,
        Action<double> reportProgress,
        PdfConversionOptions? pdfOptions)
    {
        if (!File.Exists(input))
            throw new FileNotFoundException("File sumber tidak ditemukan.", input);

        var outputDirectory = ResolveOutputDirectory(input);
        Directory.CreateDirectory(outputDirectory);
        var output = UniqueOutputPath(outputDirectory, Path.GetFileNameWithoutExtension(input), target);
        var source = PortableFileFormat.Detect(input);
        var selectedPdfOptions = pdfOptions ?? new PdfConversionOptions(
            settings.Current.PdfPageSize,
            settings.Current.PdfMargin,
            settings.Current.PdfQuality,
            settings.Current.MultiPageOutput);
        if (source.Kind == PortableMediaKind.Subtitle)
        {
            var converted = await Task.Run(() => SubtitleConverter.Convert(input, target, cancellationToken, reportProgress), cancellationToken);
            await Task.Run(() => SubtitleConverter.Write(output, converted), cancellationToken);
            reportProgress(1);
            return output;
        }
        if (source.Kind == PortableMediaKind.Archive)
        {
            await Task.Run(() => ArchiveConverter.Convert(input, target, output, cancellationToken, reportProgress), cancellationToken);
            return output;
        }
        if (source.Kind == PortableMediaKind.Image && target == "pdf")
        {
            await Task.Run(() => PdfConversion.CreateImagePdf([input], output, selectedPdfOptions, cancellationToken, reportProgress), cancellationToken);
            reportProgress(1);
            return output;
        }
        if (source.Kind == PortableMediaKind.Pdf)
        {
            var outputs = await PdfConversion.ConvertPdfAsync(input, target, output, selectedPdfOptions, cancellationToken, reportProgress);
            return outputs.FirstOrDefault() ?? throw new InvalidOperationException("Konversi PDF tidak menghasilkan file.");
        }

        var ffmpeg = ResolveFfmpegPath();
        var capabilities = TryGetCapabilities();
        if (capabilities is null || !capabilities.Supports(target))
            throw new InvalidOperationException($"FFmpeg pada perangkat ini tidak memiliki encoder atau muxer yang diperlukan untuk {target.ToUpperInvariant()}.");

        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = ffmpeg,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            }
        };
        foreach (var argument in FfmpegCommandBuilder.Build(input, output, target, capabilities, settings.Current))
            process.StartInfo.ArgumentList.Add(argument);

        var duration = await ProbeDurationAsync(input, cancellationToken);

        if (!process.Start())
            throw new InvalidOperationException("FFmpeg tidak dapat dijalankan.");

        var completed = false;
        try
        {
            using var cancellationRegistration = cancellationToken.Register(() =>
            {
                try
                {
                    if (!process.HasExited)
                        process.Kill(entireProcessTree: true);
                }
                catch
                {
                    // The process may already have exited between HasExited and Kill.
                }
            });
            cancellationToken.ThrowIfCancellationRequested();

            var errorTask = process.StandardError.ReadToEndAsync();
            while (true)
            {
                var line = await process.StandardOutput.ReadLineAsync();
                if (line is null)
                    break;
                if (line.Equals("progress=end", StringComparison.OrdinalIgnoreCase))
                    reportProgress(1);
                else if (line.StartsWith("out_time_ms=", StringComparison.OrdinalIgnoreCase))
                {
                    if (duration is > 0 && long.TryParse(line[12..], NumberStyles.Integer, CultureInfo.InvariantCulture, out var outputTime))
                        reportProgress(Math.Clamp(outputTime / 1_000_000d / duration.Value, 0, 0.99));
                    else
                        reportProgress(-1);
                }
            }

            await process.WaitForExitAsync();
            var errorOutput = await errorTask;
            cancellationToken.ThrowIfCancellationRequested();
            if (process.ExitCode != 0)
                throw new InvalidOperationException(string.IsNullOrWhiteSpace(errorOutput)
                    ? "FFmpeg gagal mengonversi file."
                    : errorOutput.Trim());
            if (!File.Exists(output))
                throw new InvalidOperationException("FFmpeg selesai tetapi file hasil tidak ditemukan.");
            completed = true;
            return output;
        }
        finally
        {
            if (!completed)
            {
                try
                {
                    if (!process.HasExited)
                        process.Kill(entireProcessTree: true);
                    await process.WaitForExitAsync();
                }
                catch
                {
                    // Preserve the original failure and best-effort cleanup.
                }
                TryDelete(output);
            }
        }
    }

    private string ResolveFfmpegPath()
    {
        var configured = settings.Current.FfmpegPath.Trim();
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured))
            return configured;

        var bundled = Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe");
        if (File.Exists(bundled))
            return bundled;
        throw new FileNotFoundException("FFmpeg belum tersedia. Pilih ffmpeg.exe di Pengaturan.");
    }

    private FfmpegCapabilities? TryGetCapabilities()
    {
        string path;
        try { path = ResolveFfmpegPath(); }
        catch { return null; }
        lock (capabilityGate)
        {
            if (!string.Equals(path, capabilityPath, StringComparison.OrdinalIgnoreCase))
            {
                capabilityPath = path;
                cachedCapabilities = null;
                capabilityTask = ProbeCapabilitiesAsync(path);
            }
            if (cachedCapabilities is not null)
                return cachedCapabilities;
            if (capabilityTask is not { IsCompleted: true })
                return null;
            try
            {
                cachedCapabilities = capabilityTask.GetAwaiter().GetResult();
                capabilityTask = null;
                return cachedCapabilities;
            }
            catch
            {
                capabilityTask = null;
                return null;
            }
        }
    }

    private void StartCapabilityProbe()
    {
        try
        {
            capabilityPath = ResolveFfmpegPath();
            capabilityTask = ProbeCapabilitiesAsync(capabilityPath);
        }
        catch
        {
            capabilityPath = null;
        }
    }

    private static Task<FfmpegCapabilities?> ProbeCapabilitiesAsync(string path) => Task.Run(() =>
    {
        try { return FfmpegCapabilities.Probe(path); }
        catch { return null; }
    });

    private async Task<double?> ProbeDurationAsync(string input, CancellationToken cancellationToken)
    {
        var configuredFfmpeg = settings.Current.FfmpegPath.Trim();
        var ffmpeg = !string.IsNullOrWhiteSpace(configuredFfmpeg) && File.Exists(configuredFfmpeg)
            ? configuredFfmpeg
            : Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe");
        var probe = Path.Combine(Path.GetDirectoryName(ffmpeg) ?? AppContext.BaseDirectory, "ffprobe.exe");
        if (!File.Exists(probe))
            return null;

        try
        {
            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = probe,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                }
            };
            foreach (var argument in new[] { "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", input })
                process.StartInfo.ArgumentList.Add(argument);
            if (!process.Start())
                return null;
            using var registration = cancellationToken.Register(() =>
            {
                try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
                catch { }
            });
            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderr = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();
            var stdout = await stdoutTask;
            await stderr;
            return process.ExitCode == 0 &&
                   double.TryParse(stdout.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var duration) &&
                   double.IsFinite(duration) && duration > 0
                ? duration
                : null;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            return null;
        }
    }

    private string ResolveOutputDirectory(string input)
    {
        var configured = settings.Current.OutputDirectory.Trim();
        return string.IsNullOrWhiteSpace(configured)
            ? Path.GetDirectoryName(input) ?? Environment.CurrentDirectory
            : configured;
    }

    private static string UniqueOutputPath(string directory, string baseName, string target)
    {
        var extension = target.Equals("gzip", StringComparison.OrdinalIgnoreCase) ? "tar.gz" : target;
        var candidate = Path.Combine(directory, $"{baseName}.{extension}");
        for (var suffix = 2; File.Exists(candidate) || Directory.Exists(candidate); suffix++)
            candidate = Path.Combine(directory, $"{baseName} {suffix}.{extension}");
        return candidate;
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
                File.Delete(path);
        }
        catch
        {
            // Never hide the original conversion failure.
        }
    }
}

