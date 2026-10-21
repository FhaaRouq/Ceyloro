using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace Ceyloro.Windows;

internal static class Program
{
    private const string MutexName = @"Global\Ceyloro_Windows_SingleInstance";

    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        if (!createdNew)
        {
            // Another instance of Ceyloro is already running.
            return;
        }

        CleanupStaleTempDirectories();

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApplicationContext());
    }

    private static void CleanupStaleTempDirectories()
    {
        try
        {
            var tempRoot = Path.GetTempPath();
            var ceyloroTemp = Path.Combine(tempRoot, "Ceyloro");
            var cutoff = DateTime.UtcNow.AddHours(-24);
            if (Directory.Exists(ceyloroTemp))
            {
                foreach (var dir in Directory.GetDirectories(ceyloroTemp))
                {
                    try
                    {
                        var info = new DirectoryInfo(dir);
                        if (info.CreationTimeUtc < cutoff)
                            Directory.Delete(dir, recursive: true);
                    }
                    catch { }
                }
            }

            foreach (var dir in Directory.GetDirectories(tempRoot, "Ceyloro-*"))
            {
                try
                {
                    var info = new DirectoryInfo(dir);
                    if (info.CreationTimeUtc < cutoff)
                        Directory.Delete(dir, recursive: true);
                }
                catch { }
            }
        }
        catch
        {
            // Best-effort cleanup
        }
    }
}
