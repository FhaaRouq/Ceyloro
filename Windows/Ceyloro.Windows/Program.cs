using System.IO;
using System.Windows.Forms;

namespace Ceyloro.Windows;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        using var instance = SingleInstanceGate.TryAcquire();
        if (instance is null)
            return;

        TempDirectoryCleanup.RemoveStaleDirectories(
            Path.Combine(Path.GetTempPath(), "Ceyloro"), DateTime.UtcNow, TimeSpan.FromHours(24));
        var openOverlayOnStartup = args.Any(argument => string.Equals(argument, "--show", StringComparison.OrdinalIgnoreCase));
        Application.Run(new TrayApplicationContext(openOverlayOnStartup));
    }
}
