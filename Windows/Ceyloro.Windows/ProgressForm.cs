namespace Ceyloro.Windows;

public sealed class ProgressForm : Form
{
    private readonly ProgressBar progressBar = new() { Dock = DockStyle.Top, Height = 22, Style = ProgressBarStyle.Continuous };
    private readonly Label statusLabel = new() { Dock = DockStyle.Top, AutoSize = true, Padding = new Padding(0, 0, 0, 10), Text = "Menyiapkan…" };
    private readonly Button cancelButton = new() { Text = "Batal", AutoSize = true, Anchor = AnchorStyles.Right | AnchorStyles.Bottom };

    public CancellationToken CancellationToken => cancellationSource.Token;
    private readonly CancellationTokenSource cancellationSource = new();

    public ProgressForm()
    {
        Text = "Ceyloro";
        Width = 420;
        Height = 150;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;
        Controls.Add(cancelButton);
        Controls.Add(progressBar);
        Controls.Add(statusLabel);
        cancelButton.Location = new Point(ClientSize.Width - cancelButton.Width - 12, ClientSize.Height - cancelButton.Height - 12);
        cancelButton.Click += (_, _) => cancellationSource.Cancel();
        FormClosing += (_, e) =>
        {
            if (!cancellationSource.IsCancellationRequested)
                cancellationSource.Cancel();
        };
    }

    public void UpdateProgress(double value)
    {
        var clamped = Math.Clamp(value, 0, 1);
        progressBar.Value = (int)Math.Round(clamped * 100);
        statusLabel.Text = $"Mengonversi… {progressBar.Value}%";
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            cancellationSource.Dispose();
        base.Dispose(disposing);
    }
}
