using System.Text.Json;

namespace Ceyloro.Windows;

public sealed class AppSettings
{
    public string OutputDirectory { get; set; } = string.Empty;
    public string FfmpegPath { get; set; } = string.Empty;
}

public sealed class SettingsStore
{
    private readonly string filePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Ceyloro",
        "settings.json");

    public AppSettings Current { get; private set; } = new();

    public static SettingsStore Load()
    {
        var store = new SettingsStore();
        try
        {
            if (File.Exists(store.filePath))
            {
                var json = File.ReadAllText(store.filePath);
                store.Current = JsonSerializer.Deserialize<AppSettings>(json) ?? new AppSettings();
            }
        }
        catch
        {
            store.Current = new AppSettings();
        }
        return store;
    }

    public void Save()
    {
        var directory = Path.GetDirectoryName(filePath);
        if (!string.IsNullOrWhiteSpace(directory))
            Directory.CreateDirectory(directory);
        var json = JsonSerializer.Serialize(Current, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(filePath, json);
    }
}
