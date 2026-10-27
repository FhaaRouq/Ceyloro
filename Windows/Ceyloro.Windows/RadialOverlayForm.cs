using System.Drawing.Drawing2D;

namespace Ceyloro.Windows;

public sealed class RadialOverlayForm : Form
{
    private readonly ConversionEngine engine;
    private readonly Action<string> showMessage;
    private readonly Rectangle virtualBounds;
    private Point center;
    private string[] draggedFiles = [];
    private string[] availableTargets = [];
    private string emptyStateMessage = "Tekan Ctrl+Alt+Space, lalu tarik file dari Explorer.";
    private int selectedIndex = -1;
    private bool isConverting;
    private bool dragOverLogged;
    private bool waitingForTargets;
    private int dragGeneration;

    public RadialWheelMode CurrentMode { get; private set; }
    public bool OpenedByGesture { get; }
    public bool IsConverting => isConverting;

    public RadialOverlayForm(ConversionEngine engine, Action<string> showMessage, bool openedByGesture = false, RadialWheelMode initialMode = RadialWheelMode.Convert)
    {
        this.engine = engine;
        this.showMessage = showMessage;
        OpenedByGesture = openedByGesture;
        CurrentMode = initialMode;
        virtualBounds = SystemInformation.VirtualScreen;
        Bounds = virtualBounds;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        AllowDrop = true;
        KeyPreview = true;
        BackColor = Color.Magenta;
        TransparencyKey = Color.Magenta;
        DoubleBuffered = true;

        var initialPos = Cursor.Position;
        var screen = Screen.FromPoint(initialPos);
        var clamped = RadialGeometry.ClampWheelCenter(initialPos, screen.WorkingArea);
        center = new Point(clamped.X - virtualBounds.Left, clamped.Y - virtualBounds.Top);

        DragEnter += OnDragEnter;
        DragOver += OnDragOver;
        DragLeave += (_, _) =>
        {
            dragGeneration++;
            waitingForTargets = false;
            selectedIndex = -1;
            Invalidate();
        };
        DragDrop += OnDragDrop;
        KeyDown += OnKeyDown;
        MouseMove += (_, _) => { UpdateSelection(Cursor.Position); Invalidate(); };
        MouseClick += OnMouseClick;
        if (!openedByGesture)
            Shown += (_, _) => Focus();
    }

    public void RepositionTo(Point cursorPosition)
    {
        var screen = Screen.FromPoint(cursorPosition);
        var clamped = RadialGeometry.ClampWheelCenter(cursorPosition, screen.WorkingArea);
        center = new Point(clamped.X - virtualBounds.Left, clamped.Y - virtualBounds.Top);
        Invalidate();
    }

    protected override bool ShowWithoutActivation => OpenedByGesture;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            if (OpenedByGesture)
                cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
            cp.ExStyle |= 0x00000008; // WS_EX_TOPMOST
            return cp;
        }
    }

    private void OnDragEnter(object? sender, DragEventArgs e)
    {
        var generation = ++dragGeneration;
        draggedFiles = ReadFiles(e.Data);
        availableTargets = [];
        waitingForTargets = draggedFiles.Length > 0;
        emptyStateMessage = draggedFiles.Length == 0 ? engine.EmptyStateFor(draggedFiles) : "Memeriksa format…";
        if (waitingForTargets)
            _ = LoadTargetsAsync(draggedFiles, generation);
        var extensions = draggedFiles.Select(path => PortableFileFormat.Detect(path).Extension).Distinct(StringComparer.OrdinalIgnoreCase);
        AppLog.Write($"DragEnter fileDrop={e.Data?.GetDataPresent(DataFormats.FileDrop) == true} files={draggedFiles.Length} extensions={string.Join(",", extensions)} targets={string.Join(",", availableTargets)} state={emptyStateMessage}");
        dragOverLogged = false;
        UpdateSelection(Cursor.Position);
        e.Effect = draggedFiles.Length > 0 ? DragDropEffects.Copy : DragDropEffects.None;
        Invalidate();
    }

    private void OnDragOver(object? sender, DragEventArgs e)
    {
        UpdateSelection(Cursor.Position);
        e.Effect = (availableTargets.Length > 0 || waitingForTargets) ? DragDropEffects.Copy : DragDropEffects.None;
        if (!dragOverLogged)
        {
            AppLog.Write($"DragOver effect={e.Effect} targets={availableTargets.Length}");
            dragOverLogged = true;
        }
        Invalidate();
    }

    public void SwitchMode(RadialWheelMode newMode)
    {
        CurrentMode = newMode;
        selectedIndex = -1;
        var generation = ++dragGeneration;
        if (draggedFiles.Length > 0)
        {
            waitingForTargets = true;
            emptyStateMessage = "Memuat pilihan…";
            _ = LoadTargetsAsync(draggedFiles, generation);
        }
        else
        {
            availableTargets = CurrentMode switch
            {
                RadialWheelMode.Actions => FileActionsEngine.AvailableActions,
                _ => []
            };
            emptyStateMessage = CurrentMode switch
            {
                RadialWheelMode.Tools => "Tarik file untuk melihat alat pengolahan",
                RadialWheelMode.Actions => "Tarik file untuk melakukan aksi",
                _ => "Tarik file untuk mengonversi format"
            };
        }
        Invalidate();
    }

    private async Task LoadTargetsAsync(string[] files, int generation)
    {
        try
        {
            var mode = CurrentMode;
            var evaluation = await Task.Run(() =>
            {
                if (mode == RadialWheelMode.Tools)
                {
                    var tools = ToolsEngine.GetApplicableTools(files, engine);
                    return (Targets: tools, Message: tools.Length == 0 ? "Tidak ada alat yang cocok untuk file ini" : string.Empty);
                }
                if (mode == RadialWheelMode.Actions)
                {
                    var actions = FileActionsEngine.AvailableActions;
                    return (Targets: actions, Message: string.Empty);
                }

                var targets = engine.TargetsFor(files).ToList();
                return (Targets: targets.ToArray(), Message: targets.Count == 0 ? engine.EmptyStateFor(files) : string.Empty);
            });
            if (IsDisposed || generation != dragGeneration) return;
            availableTargets = evaluation.Targets;
            emptyStateMessage = evaluation.Message;
        }
        catch (Exception error)
        {
            if (IsDisposed || generation != dragGeneration) return;
            availableTargets = [];
            emptyStateMessage = "Format file belum dapat diperiksa";
            AppLog.Write($"Pemeriksaan target drag gagal: {error.GetType().Name}");
        }
        finally
        {
            if (!IsDisposed && generation == dragGeneration)
            {
                waitingForTargets = false;
                UpdateSelection(Cursor.Position);
                Invalidate();
            }
        }
    }

    private async void OnDragDrop(object? sender, DragEventArgs e)
    {
        AppLog.Write($"DragDrop mode={CurrentMode} files={draggedFiles.Length} target={(selectedIndex >= 0 && selectedIndex < availableTargets.Length ? availableTargets[selectedIndex] : "none")}");
        if (isConverting || selectedIndex < 0 || selectedIndex >= availableTargets.Length)
        {
            Close();
            return;
        }

        var files = ReadFiles(e.Data);
        if (files.Length == 0)
            files = draggedFiles;

        await ExecuteSelectionAsync(files, selectedIndex);
    }

    private async Task ExecuteSelectionAsync(string[] files, int targetIndex)
    {
        if (files.Length == 0 || targetIndex < 0 || targetIndex >= availableTargets.Length)
        {
            Close();
            return;
        }

        if (CurrentMode == RadialWheelMode.Actions)
        {
            var action = availableTargets[targetIndex];
            Hide();
            FileActionsEngine.ExecuteAction(action, files, out var feedback);
            Close();
            showMessage(feedback);
            return;
        }

        if (CurrentMode == RadialWheelMode.Tools)
        {
            var tool = availableTargets[targetIndex].ToLowerInvariant();
            if (tool == "kompres")
            {
                await StartConversionAsync(files, "compress");
                return;
            }
            await StartToolExecutionAsync(files, tool);
            return;
        }

        await StartConversionAsync(files, availableTargets[targetIndex]);
    }

    private async Task StartToolExecutionAsync(string[] files, string tool)
    {
        isConverting = true;
        Hide();
        using var progress = new ProgressForm();
        progress.Show(this);
        var outputDir = engine.Settings.Current.OutputDirectory.Trim();
        if (string.IsNullOrWhiteSpace(outputDir))
            outputDir = Path.GetDirectoryName(files[0]) ?? Environment.CurrentDirectory;

        try
        {
            var outputs = new List<string>();
            foreach (var file in files)
            {
                progress.SetCurrentFile(file);
                if (tool == "mute")
                    outputs.Add(await ToolsEngine.ExecuteMuteAsync(file, outputDir, engine.Settings.Current, progress.CancellationToken));
                else if (tool == "snapshot")
                    outputs.Add(await ToolsEngine.ExecuteSnapshotAsync(file, outputDir, engine.Settings.Current, progress.CancellationToken));
                else if (tool == "ekstrak")
                    outputs.Add(await ToolsEngine.ExecuteExtractAsync(file, outputDir, progress.CancellationToken));
            }
            progress.Close();
            var summary = $"Selesai: {outputs.Count} file diproses ({tool.ToUpperInvariant()}).";
            var choice = MessageBox.Show(this, summary + "\n\nBuka folder hasil?", "Ceyloro", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (choice == DialogResult.Yes && outputs.Count > 0)
            {
                var folder = Directory.Exists(outputs[0]) ? outputs[0] : Path.GetDirectoryName(outputs[0]);
                if (!string.IsNullOrWhiteSpace(folder))
                    Process.Start(new ProcessStartInfo("explorer.exe", $"\"{folder}\"") { UseShellExecute = true });
            }
        }
        catch (OperationCanceledException)
        {
            progress.Close();
            showMessage("Operasi dibatalkan.");
        }
        catch (Exception error)
        {
            progress.Close();
            showMessage($"Operasi gagal: {error.Message}");
        }
        finally
        {
            Close();
        }
    }

    private async Task StartConversionAsync(string[] files, string target)
    {
        if (isConverting || files.Length == 0)
        {
            Close();
            return;
        }

        isConverting = true;
        var target = availableTargets[targetIndex];
        var createCombinedPdf = false;
        var combinedPdfName = "Gabungan";
        var pdfSettings = engine.Settings.Current;
        PdfConversionOptions? pdfOptions = null;
        if (target == "pdf" && files.Length > 1 && files.All(path => PortableFileFormat.Detect(path).Kind == PortableMediaKind.Image))
        {
            if (pdfSettings.AskPdfMergeEveryTime)
            {
                using var mergeDialog = new PdfMergeForm(files, engine.Settings);
                if (mergeDialog.ShowDialog(this) != DialogResult.OK)
                {
                    Close();
                    return;
                }
                files = mergeDialog.OrderedFiles.ToArray();
                createCombinedPdf = mergeDialog.CreateCombined;
                combinedPdfName = mergeDialog.OutputName;
                pdfOptions = mergeDialog.Options;
                if (mergeDialog.RememberChoice)
                {
                    pdfSettings.PdfPageSize = pdfOptions.PageSize;
                    pdfSettings.PdfMargin = pdfOptions.Margin;
                    pdfSettings.PdfQuality = pdfOptions.Quality;
                    pdfSettings.PdfMergeMode = mergeDialog.MergeMode;
                    pdfSettings.AskPdfMergeEveryTime = false;
                    try { engine.Settings.Save(); }
                    catch (Exception error)
                    {
                        MessageBox.Show(this, $"Pilihan disimpan untuk pekerjaan ini, tetapi tidak dapat disimpan sebagai preferensi: {error.Message}", "Pengaturan Ceyloro", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }
                }
            }
            else
            {
                createCombinedPdf = pdfSettings.PdfMergeMode.Equals("single", StringComparison.OrdinalIgnoreCase);
                pdfOptions = new PdfConversionOptions(pdfSettings.PdfPageSize, pdfSettings.PdfMargin, pdfSettings.PdfQuality, pdfSettings.MultiPageOutput);
            }
        }
        Hide();
        using var progress = new ProgressForm();
        progress.Show(this);
        try
        {
            var progressReporter = new Progress<double>(progress.UpdateProgress);
            var result = target == "compress"
                ? await engine.CompressAsync(files, progressReporter, progress.CancellationToken, progress.SetCurrentFile)
                : createCombinedPdf
                ? new BatchResult([await engine.MergeImagesToPdfAsync(files, combinedPdfName, pdfOptions ?? new PdfConversionOptions(), progressReporter, progress.CancellationToken)], [])
                : await engine.ConvertAsync(files, target, progressReporter, progress.CancellationToken, pdfOptions, progress.SetCurrentFile);
            progress.Close();
            var summary = target == "compress"
                ? $"Selesai: {result.Outputs.Count} file dikompres."
                : $"Selesai: {result.Outputs.Count} file {target.ToUpperInvariant()} dibuat.";
            if (result.Failures.Count > 0)
            {
                var details = string.Join("\n", result.Failures.Take(5).Select(failure => $"{Path.GetFileName(failure.Input)}: {failure.Message}"));
                summary += $"\nGagal: {result.Failures.Count} file.\n{details}";
                if (result.Failures.Count > 5) summary += $"\n… dan {result.Failures.Count - 5} lainnya.";
                AppLog.Write($"Batch selesai dengan kegagalan: {string.Join(" | ", result.Failures.Select(failure => $"{Path.GetFileName(failure.Input)}: {failure.Message}"))}");
            }
            AppLog.Write($"Batch selesai: output={result.Outputs.Count}, failure={result.Failures.Count}");
            var choice = MessageBox.Show(this, summary + "\n\nBuka folder hasil?", "Ceyloro", MessageBoxButtons.YesNo, result.Failures.Count == 0 ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
            if (choice == DialogResult.Yes && result.Outputs.Count > 0)
            {
                var folder = Directory.Exists(result.Outputs[0]) ? result.Outputs[0] : Path.GetDirectoryName(result.Outputs[0]);
                if (!string.IsNullOrWhiteSpace(folder))
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", $"\"{folder}\"") { UseShellExecute = true });
            }
        }
        catch (OperationCanceledException)
        {
            progress.Close();
            AppLog.Write("Konversi dibatalkan oleh pengguna.");
            showMessage("Konversi dibatalkan.");
        }
        catch (Exception error)
        {
            progress.Close();
            AppLog.Write($"Konversi gagal: {error}");
            showMessage(error.Message);
        }
        finally
        {
            Close();
        }
    }

    private async void OnKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Escape)
        {
            Close();
            e.Handled = true;
            e.SuppressKeyPress = true;
            return;
        }

        // Tab untuk rotasi mode: Konversi -> Alat -> Aksi -> Konversi
        if (e.KeyCode == Keys.Tab)
        {
            var nextMode = CurrentMode switch
            {
                RadialWheelMode.Convert => RadialWheelMode.Tools,
                RadialWheelMode.Tools => RadialWheelMode.Actions,
                _ => RadialWheelMode.Convert
            };
            SwitchMode(nextMode);
            e.Handled = true;
            e.SuppressKeyPress = true;
            return;
        }

        if (availableTargets.Length == 0)
            return;

        // Angka 1-9 untuk memilih petal
        if (e.KeyCode >= Keys.D1 && e.KeyCode <= Keys.D9)
        {
            var targetIdx = e.KeyCode - Keys.D1;
            if (targetIdx < availableTargets.Length)
            {
                selectedIndex = targetIdx;
                Invalidate();
                e.Handled = true;
                e.SuppressKeyPress = true;
                return;
            }
        }
        else if (e.KeyCode >= Keys.NumPad1 && e.KeyCode <= Keys.NumPad9)
        {
            var targetIdx = e.KeyCode - Keys.NumPad1;
            if (targetIdx < availableTargets.Length)
            {
                selectedIndex = targetIdx;
                Invalidate();
                e.Handled = true;
                e.SuppressKeyPress = true;
                return;
            }
        }

        // Navigasi panah untuk berpindah antar petal
        if (e.KeyCode is Keys.Right or Keys.Down)
        {
            selectedIndex = (selectedIndex + 1) % availableTargets.Length;
            Invalidate();
            e.Handled = true;
            e.SuppressKeyPress = true;
            return;
        }
        else if (e.KeyCode is Keys.Left or Keys.Up)
        {
            selectedIndex = selectedIndex <= 0 ? availableTargets.Length - 1 : selectedIndex - 1;
            Invalidate();
            e.Handled = true;
            e.SuppressKeyPress = true;
            return;
        }

        if (e.KeyCode is Keys.Enter or Keys.Return)
        {
            if (selectedIndex >= 0 && selectedIndex < availableTargets.Length && draggedFiles.Length > 0)
            {
                await ExecuteSelectionAsync(draggedFiles, selectedIndex);
                e.Handled = true;
                e.SuppressKeyPress = true;
                return;
            }
        }
    }

    private async void OnMouseClick(object? sender, MouseEventArgs e)
    {
        var local = new Point(e.X, e.Y);
        var dx = local.X - center.X;
        var dy = local.Y - center.Y;
        var radius = Math.Sqrt(dx * dx + dy * dy);

        // Jika klik di dalam hub pada baris mode switcher (dy antara -52 dan -24)
        if (radius <= 66 && dy >= -52 && dy <= -24)
        {
            if (dx < -16)
                SwitchMode(RadialWheelMode.Convert);
            else if (dx > 16)
                SwitchMode(RadialWheelMode.Actions);
            else
                SwitchMode(RadialWheelMode.Tools);
            return;
        }

        if (radius < 66 || radius > 154)
        {
            Close();
            return;
        }
        if (selectedIndex >= 0 && selectedIndex < availableTargets.Length && draggedFiles.Length > 0)
        {
            await ExecuteSelectionAsync(draggedFiles, selectedIndex);
        }
    }

    private void UpdateSelection(Point screenPoint)
    {
        var local = new Point(screenPoint.X - virtualBounds.Left, screenPoint.Y - virtualBounds.Top);
        selectedIndex = RadialGeometry.TargetIndexAt(local.X - center.X, local.Y - center.Y, availableTargets.Length);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var count = Math.Max(availableTargets.Length, 1);
        const float inner = 66;
        const float outer = 154;
        var outerRect = new RectangleF(center.X - outer, center.Y - outer, outer * 2, outer * 2);
        var hubRect = new RectangleF(center.X - inner, center.Y - inner, inner * 2, inner * 2);
        if (availableTargets.Length == 0)
        {
            using var hubBrush = new SolidBrush(Color.FromArgb(235, 32, 32, 32));
            e.Graphics.FillEllipse(hubBrush, hubRect);
            DrawModeTabs(e.Graphics, center, CurrentMode);
            DrawCentered(e.Graphics, "Ceyloro", new RectangleF(center.X - 60, center.Y - 18, 120, 22), Color.White, 12, FontStyle.Bold);
            DrawCentered(e.Graphics, emptyStateMessage, new RectangleF(center.X - 150, center.Y + 47, 300, 42), Color.White, 10, FontStyle.Bold);
            DrawCentered(e.Graphics, "Tekan Tab untuk beralih mode", new RectangleF(center.X - 165, center.Y + 87, 330, 24), Color.Gainsboro, 8.5f, FontStyle.Regular);
            return;
        }

        var sweep = 360f / count - 7;
        for (var index = 0; index < count; index++)
        {
            var start = -90 + index * (360f / count) - sweep / 2;
            var isSelected = index == selectedIndex;
            // Petal aktif memakai aksen oranye, petal netral gelap
            var color = isSelected ? Color.FromArgb(245, 255, 140, 0) : Color.FromArgb(230, 38, 38, 38);
            using var brush = new SolidBrush(color);
            e.Graphics.FillPie(brush, outerRect, start, sweep);

            // Border tipis pada petal (lebih tegas pada petal aktif)
            var borderColor = isSelected ? Color.FromArgb(255, 255, 215, 150) : Color.FromArgb(70, 255, 255, 255);
            using var pen = new Pen(borderColor, isSelected ? 1.5f : 1f);
            e.Graphics.DrawPie(pen, outerRect, start, sweep);

            var radians = (start + sweep / 2) * Math.PI / 180;
            var labelCenter = new PointF(center.X + (float)Math.Cos(radians) * 110, center.Y + (float)Math.Sin(radians) * 110);
            DrawCentered(e.Graphics, availableTargets[index].ToUpperInvariant(), new RectangleF(labelCenter.X - 62, labelCenter.Y - 14, 124, 28), Color.White, 10, FontStyle.Bold);
        }

        using var hub = new SolidBrush(Color.FromArgb(245, 22, 22, 22));
        e.Graphics.FillEllipse(hub, hubRect);
        using var hubBorderPen = new Pen(Color.FromArgb(60, 255, 255, 255), 1.5f);
        e.Graphics.DrawEllipse(hubBorderPen, hubRect);

        // Render Mode Switcher Pills di bagian atas hub
        DrawModeTabs(e.Graphics, center, CurrentMode);

        // Pusat wheel menampilkan target aktif jika ada pilihan
        if (selectedIndex >= 0 && selectedIndex < availableTargets.Length)
        {
            var activeTarget = availableTargets[selectedIndex].ToUpperInvariant();
            DrawCentered(e.Graphics, activeTarget, new RectangleF(center.X - 60, center.Y - 14, 120, 24), Color.FromArgb(255, 165, 0), 12, FontStyle.Bold);
            DrawCentered(e.Graphics, "Lepaskan untuk pilih", new RectangleF(center.X - 90, center.Y + 14, 180, 20), Color.Gainsboro, 8, FontStyle.Regular);
        }
        else
        {
            DrawCentered(e.Graphics, "Ceyloro", new RectangleF(center.X - 60, center.Y - 10, 120, 22), Color.White, 12, FontStyle.Bold);
            var modeSubtitle = CurrentMode switch
            {
                RadialWheelMode.Tools => "Alat Pengolahan",
                RadialWheelMode.Actions => "Aksi File Shell",
                _ => "Konversi Format"
            };
            DrawCentered(e.Graphics, modeSubtitle, new RectangleF(center.X - 90, center.Y + 12, 180, 18), Color.Gainsboro, 8, FontStyle.Regular);
            DrawCentered(e.Graphics, "Tekan Tab ganti mode", new RectangleF(center.X - 90, center.Y + 30, 180, 16), Color.FromArgb(160, 160, 160), 7, FontStyle.Regular);
        }
    }

    private static void DrawModeTabs(Graphics graphics, Point center, RadialWheelMode activeMode)
    {
        var modes = new[] { ("KONVERSI", RadialWheelMode.Convert), ("ALAT", RadialWheelMode.Tools), ("AKSI", RadialWheelMode.Actions) };
        var startX = center.X - 58f;
        var y = center.Y - 48f;
        var pillWidth = 38f;
        var pillHeight = 16f;

        for (var i = 0; i < modes.Length; i++)
        {
            var (name, mode) = modes[i];
            var rect = new RectangleF(startX + i * 39f, y, pillWidth, pillHeight);
            var isActive = mode == activeMode;

            if (isActive)
            {
                using var activeBg = new SolidBrush(Color.FromArgb(220, 255, 140, 0));
                graphics.FillRectangle(activeBg, rect);
            }

            var textColor = isActive ? Color.White : Color.FromArgb(160, 160, 160);
            DrawCentered(graphics, name, rect, textColor, 6.5f, isActive ? FontStyle.Bold : FontStyle.Regular);
        }
    }

    private static void DrawCentered(Graphics graphics, string text, RectangleF bounds, Color color, float size, FontStyle style)
    {
        using var font = new Font("Segoe UI", size, style);
        using var brush = new SolidBrush(color);
        var measured = graphics.MeasureString(text, font);
        graphics.DrawString(text, font, brush, bounds.X + (bounds.Width - measured.Width) / 2, bounds.Y + (bounds.Height - measured.Height) / 2);
    }

    private static string[] ReadFiles(IDataObject? data)
    {
        if (data is null || !data.GetDataPresent(DataFormats.FileDrop))
            return [];
        return data.GetData(DataFormats.FileDrop) is string[] files
            ? files.Where(File.Exists).ToArray()
            : [];
    }
}
