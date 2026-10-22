using System.Drawing.Imaging;
using System.Formats.Tar;
using System.IO.Compression;
using System.Text;
using Ceyloro.Windows;
using DrawingEncoder = System.Drawing.Imaging.Encoder;

var tests = new (string Name, Action Run)[]
{
    ("normalizes portable image and archive extensions", PortableFormatNormalization),
    ("offers only common targets for mixed image batches", MixedImageTargets),
    ("accepts gzip TAR and rejects ordinary gzip streams", GzipArchiveDetection),
    ("uses matching radial hit-test geometry for 1 through 11 targets", RadialHitTest),
    ("reports ZIP entry limits accurately", ArchiveLimitMessage),
    ("matches macOS PDF page output naming", PdfPageOutputNaming),
    ("cleans only stale Ceyloro GUID temp folders", StaleTempCleanup),
    ("uses palette-based bounded-width GIF conversion", GifFilterGraph),
    ("restricts FFmpeg input to local files", FfmpegInputProtocolPolicy),
    ("uses an explicit consistent JPEG quality policy", PdfJpegQuality),
    ("converts valid gzip TAR without leaving partial output", GzipArchiveConversion),
    ("exports every TIFF page and preserves PNG alpha", MultiPageTiffConversion),
    ("flattens transparent pixels to white in JPEG output", JpegTransparencyFlattening),
    ("cancels image conversion before writing output", ImageConversionCancellation),
    ("radial geometry hit tests sectors and boundaries correctly", RadialGeometryHitTesting)
};

var failures = new List<string>();
foreach (var (name, run) in tests)
{
    try
    {
        run();
        Console.WriteLine($"PASS {name}");
    }
    catch (Exception error)
    {
        failures.Add($"FAIL {name}: {error}");
        Console.Error.WriteLine(failures[^1]);
    }
}

Console.WriteLine($"{tests.Length - failures.Count}/{tests.Length} Windows checks passed.");
return failures.Count == 0 ? 0 : 1;

static void PortableFormatNormalization()
{
    var jpeg = PortableFileFormat.Detect("portrait.JPEG");
    Ensure(jpeg is { Extension: "jpg", Kind: PortableMediaKind.Image }, "JPEG extension was not normalized.");
    var gzip = PortableFileFormat.Detect("backup.tar.gz");
    Ensure(gzip is { Extension: "gzip", Kind: PortableMediaKind.Archive }, "TAR.GZ was not normalized.");
    Ensure(PortableFileFormat.Detect("backup.tgz").Kind == PortableMediaKind.Archive, "TGZ was not recognized as an archive.");
}

static void MixedImageTargets()
{
    var targets = PortablePlanner.TargetsFor(["one.png", "two.jpg"]);
    Ensure(targets.Contains("pdf"), "Mixed image batches should retain PDF output.");
    Ensure(!targets.Contains("png") && !targets.Contains("jpg"), "A mixed batch should not offer a target matching only one input.");
}

static void GzipArchiveDetection()
{
    using var temp = new TestDirectory();
    var tarPath = Path.Combine(temp.Path, "backup.tar");
    WriteTar(tarPath, "inside.txt", "archive data");
    var gzipTar = Path.Combine(temp.Path, "backup.tar.gz");
    using (var input = File.OpenRead(tarPath))
    using (var output = File.Create(gzipTar))
    using (var gzip = new GZipStream(output, CompressionLevel.Optimal))
        input.CopyTo(gzip);

    var ordinaryGzip = Path.Combine(temp.Path, "ordinary.gz");
    using (var output = File.Create(ordinaryGzip))
    using (var gzip = new GZipStream(output, CompressionLevel.Optimal))
    using (var writer = new StreamWriter(gzip, new UTF8Encoding(false)))
        writer.Write("not a TAR archive");

    Ensure(ArchiveConverter.IsSupportedArchive(gzipTar), "Valid gzip TAR was rejected.");
    Ensure(!ArchiveConverter.IsSupportedArchive(ordinaryGzip), "Ordinary gzip data was offered as an archive.");
}

static void RadialHitTest()
{
    for (var count = 1; count <= 11; count++)
    {
        var step = 360d / count;
        var halfPetal = (step - 7) / 2;
        for (var index = 0; index < count; index++)
        {
            var center = index * step;
            Ensure(RadialGeometry.TargetIndexAtAngle(center, count) == index, $"Sector center {index} did not map to itself for {count} targets.");
            Ensure(RadialGeometry.TargetIndexAtAngle(center + halfPetal - 0.1, count) == index, $"Petal edge did not map to sector {index} for {count} targets.");
            Ensure(RadialGeometry.TargetIndexAtAngle(center + halfPetal + 0.1, count) == -1, $"Gap after sector {index} was selectable for {count} targets.");
        }
    }
    Ensure(RadialGeometry.TargetIndexAt(0, 0, 6) == -1, "The hub must not select a target.");
    Ensure(RadialGeometry.TargetIndexAt(200, 0, 6) == -1, "The area outside the wheel must not select a target.");
}

static void ArchiveLimitMessage()
{
    Ensure(ArchiveConverter.MaximumEntriesMessage.Contains("jumlah entri", StringComparison.OrdinalIgnoreCase), "ZIP entry limit message should identify an entry-count limit.");
    Ensure(!ArchiveConverter.MaximumEntriesMessage.Contains("2 GB", StringComparison.OrdinalIgnoreCase), "ZIP entry limit message should not claim a size limit.");
}

static void PdfPageOutputNaming()
{
    Ensure(PdfConversion.PageFileName("report", 0, 3, ".jpg") == "report-01.jpg", "PDF page naming should match the macOS page naming contract.");
    Ensure(PdfConversion.PageFileName("report", 9, 12, "png") == "report-10.png", "Page number width should follow the total page count.");
    Ensure(PdfConversion.PageFileName("..", 0, 1, "png") == "Hasil-01.png", "Unsafe empty page base names should be normalized.");
}

static void StaleTempCleanup()
{
    using var temp = new TestDirectory();
    var stale = Path.Combine(temp.Path, Guid.NewGuid().ToString("N"));
    var recent = Path.Combine(temp.Path, Guid.NewGuid().ToString("N"));
    var unrelated = Path.Combine(temp.Path, "keep-me");
    Directory.CreateDirectory(stale);
    Directory.CreateDirectory(recent);
    Directory.CreateDirectory(unrelated);
    Directory.SetLastWriteTimeUtc(stale, DateTime.UtcNow.AddDays(-2));
    Directory.SetLastWriteTimeUtc(recent, DateTime.UtcNow.AddHours(-1));
    var removed = TempDirectoryCleanup.RemoveStaleDirectories(temp.Path, DateTime.UtcNow, TimeSpan.FromHours(24));
    Ensure(removed == 1 && !Directory.Exists(stale), "A stale GUID temp directory was not removed.");
    Ensure(Directory.Exists(recent) && Directory.Exists(unrelated), "Recent or unrelated temp data was removed.");
}

static void GifFilterGraph()
{
    Ensure(FfmpegCommandBuilder.GifFilterGraph.Contains("palettegen", StringComparison.Ordinal), "GIF conversion should generate an optimized palette.");
    Ensure(FfmpegCommandBuilder.GifFilterGraph.Contains("paletteuse", StringComparison.Ordinal), "GIF conversion should apply the generated palette.");
    Ensure(FfmpegCommandBuilder.GifFilterGraph.Contains("min(720", StringComparison.Ordinal), "GIF conversion should cap output width.");
}

static void FfmpegInputProtocolPolicy()
{
    var arguments = FfmpegCommandBuilder.BuildInputArguments("C:\\media\\clip.mp4");
    var whitelistIndex = Array.IndexOf(arguments.ToArray(), "-protocol_whitelist");
    var inputIndex = Array.IndexOf(arguments.ToArray(), "-i");
    Ensure(whitelistIndex >= 0 && whitelistIndex < inputIndex, "FFmpeg input whitelist must apply before the input.");
    Ensure(arguments[whitelistIndex + 1] == "file", "FFmpeg should accept only local file protocol inputs.");
}

static void PdfJpegQuality()
{
    Ensure(PdfConversion.JpegQuality(new PdfConversionOptions(Quality: "balanced")) == 85, "Balanced JPEG quality should be explicitly set to 85.");
    Ensure(PdfConversion.JpegQuality(new PdfConversionOptions(Quality: "original")) == 92, "Original JPEG quality should be explicitly set to 92.");
}

static void GzipArchiveConversion()
{
    using var temp = new TestDirectory();
    var tarPath = Path.Combine(temp.Path, "source.tar");
    WriteTar(tarPath, "inside.txt", "archive data");
    var gzipPath = Path.Combine(temp.Path, "source.gz");
    using (var input = File.OpenRead(tarPath))
    using (var output = File.Create(gzipPath))
    using (var gzip = new GZipStream(output, CompressionLevel.Optimal))
        input.CopyTo(gzip);

    var zipPath = Path.Combine(temp.Path, "converted.zip");
    ArchiveConverter.Convert(gzipPath, "zip", zipPath, CancellationToken.None, _ => { });
    using var archive = ZipFile.OpenRead(zipPath);
    Ensure(archive.Entries.Any(entry => entry.Name == "inside.txt"), "Converted ZIP is missing the TAR entry.");
    Ensure(!File.Exists(zipPath + ".ceyloro-partial"), "A partial output was left behind.");
}

static void MultiPageTiffConversion()
{
    using var temp = new TestDirectory();
    var input = Path.Combine(temp.Path, "two-pages.tiff");
    CreateMultiPageTiff(input);
    Ensure(WindowsImageConverter.FrameCount(input, "tiff") == 2, "The TIFF decoder did not report both pages.");

    var first = Path.Combine(temp.Path, "page-01.png");
    var second = Path.Combine(temp.Path, "page-02.png");
    var outputs = WindowsImageConverter.Convert(input, "png", [first, second], new AppSettings(), CancellationToken.None, _ => { });
    Ensure(outputs.Count == 2, "Both TIFF pages should be exported.");
    using var firstPage = (Bitmap)Image.FromFile(first);
    using var secondPage = (Bitmap)Image.FromFile(second);
    Ensure(firstPage.GetPixel(0, 0).R > 200, "The first TIFF page content was not retained.");
    Ensure(secondPage.GetPixel(0, 0).B > 200, "The second TIFF page content was not retained.");

    var alphaInput = Path.Combine(temp.Path, "alpha.png");
    using (var bitmap = new Bitmap(4, 4))
    {
        bitmap.SetPixel(1, 1, Color.FromArgb(0, 0, 0, 0));
        bitmap.Save(alphaInput, ImageFormat.Png);
    }
    var alphaOutput = Path.Combine(temp.Path, "alpha-output.png");
    WindowsImageConverter.Convert(alphaInput, "png", [alphaOutput], new AppSettings(), CancellationToken.None, _ => { });
    using var alphaResult = (Bitmap)Image.FromFile(alphaOutput);
    Ensure(alphaResult.GetPixel(1, 1).A == 0, "PNG conversion should preserve transparency.");
}

static void JpegTransparencyFlattening()
{
    using var temp = new TestDirectory();
    var input = Path.Combine(temp.Path, "transparent.png");
    using (var bitmap = new Bitmap(16, 16))
    {
        bitmap.SetPixel(8, 8, Color.FromArgb(0, 0, 0, 0));
        bitmap.Save(input, ImageFormat.Png);
    }
    var output = Path.Combine(temp.Path, "flattened.jpg");
    WindowsImageConverter.Convert(input, "jpg", [output], new AppSettings(), CancellationToken.None, _ => { });
    using var result = (Bitmap)Image.FromFile(output);
    var pixel = result.GetPixel(8, 8);
    Ensure(pixel.R > 220 && pixel.G > 220 && pixel.B > 220, "Transparent pixels should be flattened onto white.");
}

static void ImageConversionCancellation()
{
    using var temp = new TestDirectory();
    var input = Path.Combine(temp.Path, "source.png");
    using (var bitmap = new Bitmap(2, 2)) bitmap.Save(input, ImageFormat.Png);
    var output = Path.Combine(temp.Path, "cancelled.jpg");
    using var source = new CancellationTokenSource();
    source.Cancel();
    try
    {
        WindowsImageConverter.Convert(input, "jpg", [output], new AppSettings(), source.Token, _ => { });
        throw new InvalidOperationException("Expected cancellation was not raised.");
    }
    catch (OperationCanceledException) { }
    Ensure(!File.Exists(output), "Cancelled conversion created an output file.");
}

static void WriteTar(string path, string entryName, string contents)
{
    using var file = File.Create(path);
    using var writer = new TarWriter(file);
    using var data = new MemoryStream(Encoding.UTF8.GetBytes(contents));
    writer.WriteEntry(new PaxTarEntry(TarEntryType.RegularFile, entryName) { DataStream = data });
}

static void CreateMultiPageTiff(string path)
{
    using var first = new Bitmap(4, 4);
    using var second = new Bitmap(4, 4);
    first.SetPixel(0, 0, Color.Red);
    second.SetPixel(0, 0, Color.Blue);
    var codec = ImageCodecInfo.GetImageEncoders().Single(encoder => encoder.MimeType == "image/tiff");
    using var parameters = new EncoderParameters(1);
    parameters.Param[0] = new EncoderParameter(DrawingEncoder.SaveFlag, (long)EncoderValue.MultiFrame);
    first.Save(path, codec, parameters);
    parameters.Param[0].Dispose();
    parameters.Param[0] = new EncoderParameter(DrawingEncoder.SaveFlag, (long)EncoderValue.FrameDimensionPage);
    first.SaveAdd(second, parameters);
    parameters.Param[0].Dispose();
    parameters.Param[0] = new EncoderParameter(DrawingEncoder.SaveFlag, (long)EncoderValue.Flush);
    first.SaveAdd(parameters);
}

static void RadialGeometryHitTesting()
{
    var center = new Point(500, 500);

    // Points inside hub (< 66 radius) return -1
    Ensure(RadialGeometry.HitTest(center, center, 6) == -1, "Hub center should return -1.");
    Ensure(RadialGeometry.HitTest(center, new Point(500, 550), 6) == -1, "Inner ring point should return -1.");

    // Points outside outer radius (> 154) return -1
    Ensure(RadialGeometry.HitTest(center, new Point(500, 700), 6) == -1, "Far outside point should return -1.");

    // 0 sectors return -1
    Ensure(RadialGeometry.HitTest(center, new Point(500, 390), 0) == -1, "Zero sectors should return -1.");

    // Test for 6 sectors (step = 60 degrees):
    // Sector 0 center is at 12 o'clock: dx = 0, dy = -110 -> (500, 390)
    Ensure(RadialGeometry.HitTest(center, new Point(500, 390), 6) == 0, "Top center should be sector 0.");

    // Sector 0 boundaries for 6 sectors: -30 deg to +30 deg
    // At -25 deg (approx dx = -46, dy = -100):
    Ensure(RadialGeometry.HitTest(center, new Point(454, 400), 6) == 0, "Counter-clockwise edge of sector 0 should be sector 0.");
    // At +25 deg (approx dx = +46, dy = -100):
    Ensure(RadialGeometry.HitTest(center, new Point(546, 400), 6) == 0, "Clockwise edge of sector 0 should be sector 0.");

    // Sector 1 center is at 60 deg (dx = 95, dy = -55 -> 595, 445):
    Ensure(RadialGeometry.HitTest(center, new Point(595, 445), 6) == 1, "Sector 1 center should be index 1.");

    // Sector 3 center is at 180 deg (6 o'clock, dx = 0, dy = 110 -> 500, 610):
    Ensure(RadialGeometry.HitTest(center, new Point(500, 610), 6) == 3, "Bottom center should be sector 3.");

    // Test with N = 1 (whole ring is sector 0)
    Ensure(RadialGeometry.HitTest(center, new Point(500, 390), 1) == 0, "N=1 top should be sector 0.");
    Ensure(RadialGeometry.HitTest(center, new Point(500, 610), 1) == 0, "N=1 bottom should be sector 0.");

    // Test with N = 4 (step = 90 deg: sector 0 = top, 1 = right, 2 = bottom, 3 = left)
    Ensure(RadialGeometry.HitTest(center, new Point(500, 390), 4) == 0, "N=4 top should be sector 0.");
    Ensure(RadialGeometry.HitTest(center, new Point(610, 500), 4) == 1, "N=4 right should be sector 1.");
    Ensure(RadialGeometry.HitTest(center, new Point(500, 610), 4) == 2, "N=4 bottom should be sector 2.");
    Ensure(RadialGeometry.HitTest(center, new Point(390, 500), 4) == 3, "N=4 left should be sector 3.");
}

static void Ensure(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

sealed class TestDirectory : IDisposable
{
    public TestDirectory()
    {
        Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "Ceyloro.Tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path);
    }

    public string Path { get; }

    public void Dispose()
    {
        try { Directory.Delete(Path, recursive: true); }
        catch { }
    }
}

