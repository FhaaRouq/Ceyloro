using System.Diagnostics;

namespace Ceyloro.Windows;

public sealed record ConversionFailure(string Input, string Message);
public sealed record BatchResult(IReadOnlyList<string> Outputs, IReadOnlyList<ConversionFailure> Failures);

public sealed class ConversionEngine
{
    private readonly SettingsStore settings;

    public ConversionEngine(SettingsStore settings)
    {
        this.settings = settings;
    }

    public async Task<BatchResult> ConvertAsync(
        IReadOnlyList<string> inputs,
        string target,
        IProgress<double>? progress,
        CancellationToken cancellationToken)
    {
        var outputs = new List<string>();
        var failures = new List<ConversionFailure>();
        var total = Math.Max(inputs.Count, 1);

        for (var index = 0; index < inputs.Count; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                var output = await ConvertOneAsync(inputs[index], target, cancellationToken,
                    value => progress?.Report((index + value) / total));
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

    private async Task<string> ConvertOneAsync(
        string input,
        string target,
        CancellationToken cancellationToken,
        Action<double> reportProgress)
    {
        if (!File.Exists(input))
            throw new FileNotFoundException("File sumber tidak ditemukan.", input);

        var ffmpeg = ResolveFfmpegPath();
        var outputDirectory = ResolveOutputDirectory(input);
        Directory.CreateDirectory(outputDirectory);
        var output = UniqueOutputPath(outputDirectory, Path.GetFileNameWithoutExtension(input), target);

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
        process.StartInfo.ArgumentList.Add("-hide_banner");
        process.StartInfo.ArgumentList.Add("-loglevel");
        process.StartInfo.ArgumentList.Add("error");
        process.StartInfo.ArgumentList.Add("-nostdin");
        process.StartInfo.ArgumentList.Add("-y");
        process.StartInfo.ArgumentList.Add("-i");
        process.StartInfo.ArgumentList.Add(input);
        process.StartInfo.ArgumentList.Add("-progress");
        process.StartInfo.ArgumentList.Add("pipe:1");
        process.StartInfo.ArgumentList.Add("-nostats");
        process.StartInfo.ArgumentList.Add(output);

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

        if (!process.Start())
            throw new InvalidOperationException("FFmpeg tidak dapat dijalankan.");

        var errorTask = process.StandardError.ReadToEndAsync();
        while (!process.HasExited)
        {
            var line = await process.StandardOutput.ReadLineAsync(cancellationToken);
            if (line is null)
                break;
            if (line.Equals("progress=end", StringComparison.OrdinalIgnoreCase))
                reportProgress(1);
        }

        await process.WaitForExitAsync(cancellationToken);
        var errorOutput = await errorTask;
        if (cancellationToken.IsCancellationRequested)
            throw new OperationCanceledException(cancellationToken);
        if (process.ExitCode != 0)
        {
            TryDelete(output);
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(errorOutput)
                ? "FFmpeg gagal mengonversi file."
                : errorOutput.Trim());
        }
        if (!File.Exists(output))
            throw new InvalidOperationException("FFmpeg selesai tetapi file hasil tidak ditemukan.");
        return output;
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
        for (var suffix = 2; File.Exists(candidate); suffix++)
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
