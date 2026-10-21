namespace Ceyloro.Windows;

internal static class AppLog
{
    private static readonly object gate = new();
    private static readonly string directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Ceyloro", "Logs");
    private static readonly string filePath = Path.Combine(directory, "app.log");
    private const long MaximumBytes = 2 * 1024 * 1024;

    public static void Write(string message)
    {
        lock (gate)
        {
            try
            {
                Directory.CreateDirectory(directory);
                var info = new FileInfo(filePath);
                if (info.Exists && info.Length > MaximumBytes)
                {
                    var previous = filePath + ".1";
                    if (File.Exists(previous)) File.Delete(previous);
                    File.Move(filePath, previous);
                }
                File.AppendAllText(filePath, $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
            }
            catch { }
        }
    }
}
