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

