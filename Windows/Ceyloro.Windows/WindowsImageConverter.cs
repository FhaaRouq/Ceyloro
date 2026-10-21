using System.Drawing.Imaging;

namespace Ceyloro.Windows;

internal static class WindowsImageConverter
{
    public static bool CanDecode(string extension) => extension is "jpg" or "png" or "tiff" or "bmp" or "gif";

    public static int FrameCount(string input, string extension)
    {
        if (extension != "tiff") return 1;
        using var image = Image.FromFile(input);
        return Math.Max(1, image.GetFrameCount(FrameDimension.Page));
    }

    public static IReadOnlyList<string> Convert(
        string input,
        string target,
        IReadOnlyList<string> outputs,
        AppSettings settings,
        CancellationToken cancellationToken,
        Action<double> progress)
    {
        if (!CanDecode(Path.GetExtension(input).TrimStart('.').ToLowerInvariant()) || target is not ("jpg" or "png" or "tiff"))
            throw new InvalidOperationException("Format gambar ini tidak didukung oleh konverter gambar Windows.");
        var extension = Path.GetExtension(input).TrimStart('.').ToLowerInvariant();
        var count = FrameCount(input, extension);
        if (outputs.Count != count)
            throw new InvalidOperationException("Jumlah file hasil tidak sesuai dengan jumlah halaman gambar.");

        var completed = new List<string>();
        try
        {
            for (var index = 0; index < count; index++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                using var source = Image.FromFile(input);
                if (extension == "tiff") source.SelectActiveFrame(FrameDimension.Page, index);
                PdfConversion.ApplyExifOrientation(source);
                var partial = outputs[index] + ".ceyloro-partial";
                try
                {
                    if (target == "jpg")
                        SaveJpeg(source, partial, settings.JpgQuality);
                    else
                        source.Save(partial, target == "png" ? ImageFormat.Png : ImageFormat.Tiff);
                    File.Move(partial, outputs[index]);
                    completed.Add(outputs[index]);
                }
                finally
                {
                    try { if (File.Exists(partial)) File.Delete(partial); }
                    catch { }
                }
                progress((index + 1d) / count);
            }
            return completed;
        }
        catch
        {
            foreach (var output in completed)
            {
                try { if (File.Exists(output)) File.Delete(output); }
                catch { }
            }
            throw;
        }
    }

    private static void SaveJpeg(Image source, string path, double quality)
    {
        using var flattened = new Bitmap(source.Width, source.Height, PixelFormat.Format24bppRgb);
        using (var graphics = Graphics.FromImage(flattened))
        {
            graphics.Clear(Color.White);
            graphics.DrawImage(source, 0, 0, source.Width, source.Height);
        }
        var codec = ImageCodecInfo.GetImageEncoders().First(encoder => encoder.MimeType == "image/jpeg");
        using var parameters = new EncoderParameters(1);
        var value = Math.Clamp((long)Math.Round(quality * 100), 10, 100);
        parameters.Param[0] = new EncoderParameter(Encoder.Quality, value);
        flattened.Save(path, codec, parameters);
    }
}

