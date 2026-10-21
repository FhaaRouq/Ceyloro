namespace Ceyloro.Windows;

internal sealed class PdfMergeForm : Form
{
    private readonly List<string> files;
    private readonly ListBox fileList = new() { Dock = DockStyle.Fill, IntegralHeight = false };
    private readonly TextBox outputName = new() { Dock = DockStyle.Fill, Text = "Gabungan" };
    private readonly ComboBox pageSize = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox margin = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox quality = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox mode = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly CheckBox remember = new() { Text = "Ingat pilihan dan jangan tanya lagi", AutoSize = true };
    private readonly SettingsStore settings;

    public IReadOnlyList<string> OrderedFiles => files;
    public string OutputName => outputName.Text.Trim();
    public bool CreateCombined => mode.SelectedIndex == 0;
    public bool RememberChoice => remember.Checked;
    public string MergeMode => CreateCombined ? "single" : "each";
    public PdfConversionOptions Options => new(
        pageSize.SelectedIndex switch { 1 => "letter", 2 => "matchImage", _ => "a4" },
        margin.SelectedIndex == 1 ? "medium" : "none",
        quality.SelectedIndex == 1 ? "original" : "balanced",
        settings.Current.MultiPageOutput);

    public PdfMergeForm(IEnumerable<string> inputFiles, SettingsStore settings)
    {
        this.settings = settings;
        files = inputFiles.ToList();
        Text = "Buat PDF";
        ClientSize = new Size(650, 500);
        MinimumSize = new Size(540, 430);
        StartPosition = FormStartPosition.CenterParent;
        ShowInTaskbar = false;

        pageSize.Items.AddRange(["A4", "Letter", "Sesuai gambar"]);
        margin.Items.AddRange(["Tanpa margin", "Margin sedang"]);
        quality.Items.AddRange(["Seimbang", "Asli"]);
        mode.Items.AddRange(["Satu PDF gabungan", "Satu PDF per gambar"]);
        var current = settings.Current;
        pageSize.SelectedIndex = current.PdfPageSize.ToLowerInvariant() switch { "letter" => 1, "matchimage" => 2, _ => 0 };
        margin.SelectedIndex = current.PdfMargin.Equals("medium", StringComparison.OrdinalIgnoreCase) ? 1 : 0;
        quality.SelectedIndex = current.PdfQuality.Equals("original", StringComparison.OrdinalIgnoreCase) ? 1 : 0;
        mode.SelectedIndex = current.PdfMergeMode.Equals("each", StringComparison.OrdinalIgnoreCase) ? 1 : 0;
        remember.Checked = !current.AskPdfMergeEveryTime;
        outputName.Text = "Gabungan";
        RefreshFiles();

        var root = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(14), ColumnCount = 2, RowCount = 7 };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 160));
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));

        var listPanel = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1 };
        listPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        listPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 42));
        listPanel.Controls.Add(fileList, 0, 0);
        var orderButtons = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false };
        var up = new Button { Text = "↑", Width = 36, Height = 32, AccessibleName = "Pindah ke atas" };
        var down = new Button { Text = "↓", Width = 36, Height = 32, AccessibleName = "Pindah ke bawah" };
        up.Click += (_, _) => MoveSelected(-1);
        down.Click += (_, _) => MoveSelected(1);
        orderButtons.Controls.Add(up);
        orderButtons.Controls.Add(down);
        listPanel.Controls.Add(orderButtons, 1, 0);
        root.Controls.Add(listPanel, 0, 0);
        root.SetColumnSpan(listPanel, 2);
        AddSettingRow(root, 1, "Mode", mode);
        AddSettingRow(root, 2, "Ukuran halaman", pageSize);
        AddSettingRow(root, 3, "Margin", margin);
        AddSettingRow(root, 4, "Kualitas", quality);
        AddSettingRow(root, 5, "Nama PDF gabungan", outputName);
        root.Controls.Add(remember, 0, 6);
        root.SetColumnSpan(remember, 2);
        Controls.Add(root);

        var cancel = new Button { Text = "Batal", DialogResult = DialogResult.Cancel, AutoSize = true };
        var create = new Button { Text = "Buat PDF", DialogResult = DialogResult.OK, AutoSize = true };
        var footer = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(8) };
        footer.Controls.Add(cancel);
        footer.Controls.Add(create);
        Controls.Add(footer);
        AcceptButton = create;
        CancelButton = cancel;
    }

    private static void AddSettingRow(TableLayoutPanel grid, int row, string label, Control control)
    {
        grid.Controls.Add(new Label { Text = label, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, row);
        control.Dock = DockStyle.Fill;
        grid.Controls.Add(control, 1, row);
    }

    private void RefreshFiles()
    {
        fileList.Items.Clear();
        foreach (var path in files) fileList.Items.Add(Path.GetFileName(path));
        if (files.Count > 0) fileList.SelectedIndex = Math.Min(fileList.SelectedIndex, files.Count - 1);
    }

    private void MoveSelected(int offset)
    {
        var index = fileList.SelectedIndex;
        var next = index + offset;
        if (index < 0 || next < 0 || next >= files.Count) return;
        (files[index], files[next]) = (files[next], files[index]);
        RefreshFiles();
        fileList.SelectedIndex = next;
    }
}
