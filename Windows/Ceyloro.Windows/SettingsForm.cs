namespace Ceyloro.Windows;

public sealed class SettingsForm : Form
{
    private readonly SettingsStore store;
    private readonly TextBox outputBox = new() { Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right };
    private readonly TextBox ffmpegBox = new() { Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right };

    public SettingsForm(SettingsStore store)
    {
        this.store = store;
        Text = "Pengaturan Ceyloro";
        Width = 620;
        Height = 210;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;

        outputBox.Text = store.Current.OutputDirectory;
        ffmpegBox.Text = store.Current.FfmpegPath;
        AddRow("Folder output", outputBox, BrowseOutput);
        AddRow("FFmpeg", ffmpegBox, BrowseFfmpeg);

        var save = new Button { Text = "Simpan", AutoSize = true, DialogResult = DialogResult.OK };
        save.Click += (_, _) =>
        {
            store.Current.OutputDirectory = outputBox.Text.Trim();
            store.Current.FfmpegPath = ffmpegBox.Text.Trim();
            store.Save();
        };
        var cancel = new Button { Text = "Batal", AutoSize = true, DialogResult = DialogResult.Cancel };
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(8) };
        buttons.Controls.Add(cancel);
        buttons.Controls.Add(save);
        Controls.Add(buttons);
        AcceptButton = save;
        CancelButton = cancel;
    }

    private void AddRow(string labelText, TextBox box, Action browse)
    {
        var row = new TableLayoutPanel { Dock = DockStyle.Top, Height = 55, ColumnCount = 3, Padding = new Padding(12, 10, 12, 0) };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90));
        row.Controls.Add(new Label { Text = labelText, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, 0);
        row.Controls.Add(box, 1, 0);
        var button = new Button { Text = "Pilih…", Dock = DockStyle.Fill };
        button.Click += (_, _) => browse();
        row.Controls.Add(button, 2, 0);
        Controls.Add(row);
    }

    private void BrowseOutput()
    {
        using var dialog = new FolderBrowserDialog { Description = "Pilih folder output" };
        if (dialog.ShowDialog(this) == DialogResult.OK)
            outputBox.Text = dialog.SelectedPath;
    }

    private void BrowseFfmpeg()
    {
        using var dialog = new OpenFileDialog { Filter = "FFmpeg|ffmpeg.exe|Semua file|*.*", Title = "Pilih ffmpeg.exe" };
        if (dialog.ShowDialog(this) == DialogResult.OK)
            ffmpegBox.Text = dialog.FileName;
    }
}
