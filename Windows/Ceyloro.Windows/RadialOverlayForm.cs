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
    private int selectedIndex = -1;
    private bool isConverting;

    public RadialOverlayForm(ConversionEngine engine, Action<string> showMessage)
    {
        this.engine = engine;
        this.showMessage = showMessage;
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
        center = new Point(Cursor.Position.X - virtualBounds.Left, Cursor.Position.Y - virtualBounds.Top);
        DragEnter += OnDragEnter;
        DragOver += OnDragOver;
        DragLeave += (_, _) => { selectedIndex = -1; Invalidate(); };
        DragDrop += OnDragDrop;
        KeyDown += OnKeyDown;
        Shown += (_, _) => Focus();
    }

    private void OnDragEnter(object? sender, DragEventArgs e)
    {
        draggedFiles = ReadFiles(e.Data);
        availableTargets = PortablePlanner.TargetsFor(draggedFiles).ToArray();
        e.Effect = draggedFiles.Length > 0 && availableTargets.Length > 0 ? DragDropEffects.Copy : DragDropEffects.None;
        UpdateSelection(Cursor.Position);
        Invalidate();
    }

    private void OnDragOver(object? sender, DragEventArgs e)
    {
        e.Effect = availableTargets.Length > 0 ? DragDropEffects.Copy : DragDropEffects.None;
        UpdateSelection(Cursor.Position);
        Invalidate();
    }

    private async void OnDragDrop(object? sender, DragEventArgs e)
    {
        if (isConverting || selectedIndex < 0 || selectedIndex >= availableTargets.Length)
        {
            Close();
            return;
        }

        isConverting = true;
        var files = ReadFiles(e.Data);
        var target = availableTargets[selectedIndex];
        Hide();
        using var progress = new ProgressForm();
        progress.Show(this);
        try
        {
            var progressReporter = new Progress<double>(progress.UpdateProgress);
            var result = await engine.ConvertAsync(files, target, progressReporter, progress.CancellationToken);
            progress.Close();
            var summary = $"Selesai: {result.Outputs.Count} file {target.ToUpperInvariant()} dibuat.";
            if (result.Failures.Count > 0)
                summary += $"\nGagal: {result.Failures.Count} file.";
            showMessage(summary);
        }
        catch (OperationCanceledException)
        {
            progress.Close();
            showMessage("Konversi dibatalkan.");
        }
        catch (Exception error)
        {
            progress.Close();
            showMessage(error.Message);
        }
        finally
        {
            Close();
        }
    }

    private void OnKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Escape)
        {
            Close();
            return;
        }
        if (availableTargets.Length == 0)
            return;
        if (e.KeyCode >= Keys.D1 && e.KeyCode <= Keys.D9)
            selectedIndex = Math.Min((int)e.KeyCode - (int)Keys.D1, availableTargets.Length - 1);
        else if (e.KeyCode == Keys.Right || e.KeyCode == Keys.Down)
            selectedIndex = (selectedIndex + 1 + availableTargets.Length) % availableTargets.Length;
        else if (e.KeyCode == Keys.Left || e.KeyCode == Keys.Up)
            selectedIndex = (selectedIndex - 1 + availableTargets.Length) % availableTargets.Length;
        Invalidate();
    }

    private void UpdateSelection(Point screenPoint)
    {
        var local = new Point(screenPoint.X - virtualBounds.Left, screenPoint.Y - virtualBounds.Top);
        var dx = local.X - center.X;
        var dy = local.Y - center.Y;
        var radius = Math.Sqrt(dx * dx + dy * dy);
        if (radius is < 66 or > 154 || availableTargets.Length == 0)
        {
            selectedIndex = -1;
            return;
        }
        var degrees = Math.Atan2(dy, dx) * 180 / Math.PI + 90;
        if (degrees < 0) degrees += 360;
        selectedIndex = (int)(degrees / (360d / availableTargets.Length)) % availableTargets.Length;
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
            DrawCentered(e.Graphics, "Tarik file ke sini", hubRect, Color.White, 13, FontStyle.Bold);
            return;
        }

        var sweep = 360f / count - 7;
        for (var index = 0; index < count; index++)
        {
            var start = -90 + index * (360f / count) - sweep / 2;
            var color = index == selectedIndex ? Color.FromArgb(196, 180, 224, 92) : Color.FromArgb(230, 38, 38, 38);
            using var brush = new SolidBrush(color);
            e.Graphics.FillPie(brush, outerRect, start, sweep);
            var radians = (start + sweep / 2) * Math.PI / 180;
            var labelCenter = new PointF(center.X + (float)Math.Cos(radians) * 110, center.Y + (float)Math.Sin(radians) * 110);
            DrawCentered(e.Graphics, $"{index + 1}  {availableTargets[index].ToUpperInvariant()}", new RectangleF(labelCenter.X - 62, labelCenter.Y - 14, 124, 28), Color.White, 10, FontStyle.Bold);
        }
        using var hub = new SolidBrush(Color.FromArgb(245, 22, 22, 22));
        e.Graphics.FillEllipse(hub, hubRect);
        DrawCentered(e.Graphics, "Ceyloro", new RectangleF(center.X - 60, center.Y - 12, 120, 24), Color.White, 13, FontStyle.Bold);
        DrawCentered(e.Graphics, "Esc untuk batal", new RectangleF(center.X - 70, center.Y + 20, 140, 20), Color.Gainsboro, 8, FontStyle.Regular);
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
