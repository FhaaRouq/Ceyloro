using System.Collections.Specialized;
using System.Diagnostics;

namespace Ceyloro.Windows;

public static class FileActionsEngine
{
    public static readonly string[] AvailableActions = ["salin path", "terminal", "buka folder", "salin file"];

    public static bool ExecuteAction(string action, string[] files, out string feedbackMessage)
    {
        feedbackMessage = string.Empty;
        if (files.Length == 0)
        {
            feedbackMessage = "Tidak ada file yang dipilih.";
            return false;
        }

        try
        {
            switch (action.ToLowerInvariant())
            {
                case "salin path":
                    var formattedPaths = string.Join(Environment.NewLine, files);
                    Clipboard.SetText(formattedPaths);
                    feedbackMessage = files.Length == 1
                        ? $"Path disalin ke clipboard:\n{Path.GetFileName(files[0])}"
                        : $"{files.Length} path berkas disalin ke clipboard.";
                    return true;

                case "terminal":
                    var targetDir = Directory.Exists(files[0])
                        ? files[0]
                        : Path.GetDirectoryName(files[0]) ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

                    LaunchTerminal(targetDir);
                    feedbackMessage = $"Terminal dibuka di: {targetDir}";
                    return true;

                case "buka folder":
                    var firstFile = files[0];
                    if (File.Exists(firstFile))
                    {
                        Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{firstFile}\"") { UseShellExecute = true });
                    }
                    else if (Directory.Exists(firstFile))
                    {
                        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{firstFile}\"") { UseShellExecute = true });
                    }
                    feedbackMessage = "Folder dibuka di Explorer.";
                    return true;

                case "salin file":
                    var collection = new StringCollection();
                    foreach (var f in files)
                    {
                        if (File.Exists(f) || Directory.Exists(f))
                            collection.Add(f);
                    }
                    Clipboard.SetFileDropList(collection);
                    feedbackMessage = files.Length == 1
                        ? $"Berkas disalin ke clipboard (Ctrl+V): {Path.GetFileName(files[0])}"
                        : $"{files.Length} berkas disalin ke clipboard (Ctrl+V).";
                    return true;

                default:
                    feedbackMessage = $"Aksi '{action}' belum didukung.";
                    return false;
            }
        }
        catch (Exception ex)
        {
            feedbackMessage = $"Gagal mengeksekusi aksi '{action}': {ex.Message}";
            AppLog.Write($"FileActionsEngine error: {ex}");
            return false;
        }
    }

    private static void LaunchTerminal(string directory)
    {
        try
        {
            // Coba Windows Terminal terlebih dahulu
            var startInfo = new ProcessStartInfo
            {
                FileName = "wt.exe",
                Arguments = $"-d \"{directory}\"",
                UseShellExecute = true
            };
            Process.Start(startInfo);
        }
        catch
        {
            try
            {
                // Fallback ke PowerShell
                var startInfo = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-NoExit -Command \"Set-Location -LiteralPath '{directory.Replace("'", "''")}'\"",
                    UseShellExecute = true
                };
                Process.Start(startInfo);
            }
            catch
            {
                // Fallback ke Command Prompt
                Process.Start(new ProcessStartInfo
                {
                    FileName = "cmd.exe",
                    Arguments = $"/k cd /d \"{directory}\"",
                    UseShellExecute = true
                });
            }
        }
    }
}

