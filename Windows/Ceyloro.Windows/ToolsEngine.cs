using System.Diagnostics;
using System.IO.Compression;

namespace Ceyloro.Windows;

public static class ToolsEngine
{
    public static string[] GetApplicableTools(string[] files, ConversionEngine engine)
    {
        if (files.Length == 0) return [];

        var tools = new List<string>();
        var formats = files.Select(PortableFileFormat.Detect).ToArray();

        // 1. Kompres selalu ditawarkan jika didukung
        if (engine.CanCompress(files))
        {
            tools.Add("kompres");
        }

        // 2. Video Mute & Snapshot jika seluruh file adalah video
        if (formats.All(f => f.Kind == PortableMediaKind.Video))
        {
            tools.Add("mute");
            tools.Add("snapshot");
        }

        // 3. Ekstrak jika seluruh file adalah arsip
        if (formats.All(f => f.Kind == PortableMediaKind.Archive))
        {
            tools.Add("ekstrak");
        }

        return tools.ToArray();
    }

    public static async Task<string> ExecuteMuteAsync(string input, string outputDir, AppSettings settings, CancellationToken cancellationToken)
    {
        var baseName = Path.GetFileNameWithoutExtension(input);
        var ext = Path.GetExtension(input);
        var outputPath = UniqueOutputPath(outputDir, $"{baseName}-mute", ext.TrimStart('.'));

        var ffmpeg = ResolveFfmpeg(settings);
        var args = new[] { "-y", "-i", input, "-c:v", "copy", "-an", outputPath };

        await RunProcessAsync(ffmpeg, args, cancellationToken);
        if (!File.Exists(outputPath) || new FileInfo(outputPath).Length == 0)
            throw new InvalidOperationException("Gagal membungkam video (output tidak dihasilkan).");

        return outputPath;
    }

    public static async Task<string> ExecuteSnapshotAsync(string input, string outputDir, AppSettings settings, CancellationToken cancellationToken)
    {
        var baseName = Path.GetFileNameWithoutExtension(input);
        var outputPath = UniqueOutputPath(outputDir, $"{baseName}-snapshot", "png");

        var ffmpeg = ResolveFfmpeg(settings);
        // Ambil frame pada detik 1.0 (menghindari intro hitam)
        var args = new[] { "-y", "-ss", "00:00:01.000", "-i", input, "-frames:v", "1", "-q:v", "2", outputPath };

        await RunProcessAsync(ffmpeg, args, cancellationToken);
        if (!File.Exists(outputPath) || new FileInfo(outputPath).Length == 0)
            throw new InvalidOperationException("Gagal mengambil snapshot frame video.");

        return outputPath;
    }

    public static Task<string> ExecuteExtractAsync(string input, string outputDir, CancellationToken cancellationToken)
    {
        return Task.Run(() =>
        {
            var baseName = Path.GetFileNameWithoutExtension(input);
            if (baseName.EndsWith(".tar", StringComparison.OrdinalIgnoreCase))
                baseName = Path.GetFileNameWithoutExtension(baseName);

            var targetFolder = Path.Combine(outputDir, baseName);
            for (var suffix = 2; Directory.Exists(targetFolder) || File.Exists(targetFolder); suffix++)
                targetFolder = Path.Combine(outputDir, $"{baseName} {suffix}");

            Directory.CreateDirectory(targetFolder);

            var format = PortableFileFormat.Detect(input);
            if (format.Extension == "zip")
            {
                using var archive = ZipFile.OpenRead(input);
                var totalBytes = 0L;
                const long maxExtractionSize = 2L * 1024 * 1024 * 1024; // 2 GB limit
                const int maxEntries = 100000;

                if (archive.Entries.Count > maxEntries)
                    throw new InvalidDataException($"Arsip melampaui batas maksimum {maxEntries} entri.");

                foreach (var entry in archive.Entries)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    var destinationPath = Path.GetFullPath(Path.Combine(targetFolder, entry.FullName));
                    if (!destinationPath.StartsWith(Path.GetFullPath(targetFolder) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException($"Deteksi path traversal berbahaya (Zip-Slip): {entry.FullName}");

                    if (string.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(destinationPath);
                        continue;
                    }

                    totalBytes += entry.Length;
                    if (totalBytes > maxExtractionSize)
                        throw new InvalidDataException("Ukuran total ekstraksi melebihi batas aman 2 GB.");

                    Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
                    entry.ExtractToFile(destinationPath, overwrite: true);
                }
            }
            else
            {
                // Ekstraksi TAR / TAR.GZ via ArchiveConverter
                var tempZip = Path.Combine(Path.GetTempPath(), "Ceyloro", Guid.NewGuid().ToString("N") + ".zip");
                try
                {
                    ArchiveConverter.Convert(input, "zip", tempZip, cancellationToken, _ => { });
                    ZipFile.ExtractToDirectory(tempZip, targetFolder, overwriteFiles: true);
                }
                finally
                {
                    try { if (File.Exists(tempZip)) File.Delete(tempZip); } catch { }
                }
            }

            return targetFolder;
        }, cancellationToken);
    }

    private static string ResolveFfmpeg(AppSettings settings)
    {
        var configured = settings.FfmpegPath.Trim();
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured))
            return configured;
        var bundled = Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe");
        if (File.Exists(bundled))
            return bundled;
        return "ffmpeg.exe";
    }

    private static async Task RunProcessAsync(string executable, IEnumerable<string> arguments, CancellationToken cancellationToken)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = executable,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            }
        };
        foreach (var arg in arguments)
            process.StartInfo.ArgumentList.Add(arg);

        if (!process.Start())
            throw new InvalidOperationException($"Gagal menjalankan proses: {executable}");

        using var reg = cancellationToken.Register(() =>
        {
            try { if (!process.HasExited) process.Kill(true); } catch { }
        });

        var stderrTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync(cancellationToken);
        var stderr = await stderrTask;

        if (process.ExitCode != 0)
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(stderr) ? "Operasi tool media gagal." : stderr.Trim());
    }

    private static string UniqueOutputPath(string directory, string baseName, string extension)
    {
        var candidate = Path.Combine(directory, $"{baseName}.{extension}");
        for (var suffix = 2; File.Exists(candidate) || Directory.Exists(candidate); suffix++)
            candidate = Path.Combine(directory, $"{baseName} {suffix}.{extension}");
        return candidate;
    }
}
