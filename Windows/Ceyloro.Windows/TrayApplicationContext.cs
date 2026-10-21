using System.Runtime.InteropServices;

namespace Ceyloro.Windows;

public sealed class TrayApplicationContext : ApplicationContext
{
    private readonly SettingsStore settings = SettingsStore.Load();
    private readonly ConversionEngine engine;
    private readonly NotifyIcon trayIcon;
    private readonly HotKeyWindow hotKeyWindow;
    private RadialOverlayForm? overlay;
    private SettingsForm? settingsForm;

    public TrayApplicationContext()
    {
        engine = new ConversionEngine(settings);
        trayIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "Ceyloro",
            Visible = true,
            ContextMenuStrip = BuildMenu()
        };
        trayIcon.DoubleClick += (_, _) => OpenOverlay();
        hotKeyWindow = new HotKeyWindow(OpenOverlay);
        if (!hotKeyWindow.Register())
            trayIcon.ShowBalloonTip(3000, "Ceyloro", "Hotkey Ctrl+Alt+Space tidak tersedia.", ToolTipIcon.Warning);
    }

    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("Buka roda", null, (_, _) => OpenOverlay());
        menu.Items.Add("Pengaturan…", null, (_, _) => OpenSettings());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Keluar", null, (_, _) => ExitThread());
        return menu;
    }

    private void OpenOverlay()
    {
        if (overlay is { IsDisposed: false })
        {
            overlay.Activate();
            return;
        }
        overlay = new RadialOverlayForm(engine, ShowMessage);
        overlay.FormClosed += (_, _) => overlay = null;
        overlay.Show();
    }

    private void OpenSettings()
    {
        if (settingsForm is { IsDisposed: false })
        {
            settingsForm.Activate();
            return;
        }
        settingsForm = new SettingsForm(settings);
        settingsForm.FormClosed += (_, _) => settingsForm = null;
        settingsForm.Show();
        settingsForm.Activate();
    }

    private void ShowMessage(string message)
    {
        trayIcon.ShowBalloonTip(5000, "Ceyloro", message, ToolTipIcon.Info);
    }

    protected override void ExitThreadCore()
    {
        hotKeyWindow.Dispose();
        trayIcon.Visible = false;
        trayIcon.Dispose();
        overlay?.Close();
        settingsForm?.Close();
        base.ExitThreadCore();
    }
}

internal sealed class HotKeyWindow : NativeWindow, IDisposable
{
    private const int WmHotKey = 0x0312;
    private const uint ModControl = 0x0002;
    private const uint ModAlt = 0x0001;
    private const uint VkSpace = 0x20;
    private const int HotKeyId = 0xCE71;
    private readonly Action action;
    private bool registered;

    public HotKeyWindow(Action action)
    {
        this.action = action;
        CreateHandle(new CreateParams());
    }

    public bool Register()
    {
        registered = RegisterHotKey(Handle, HotKeyId, ModControl | ModAlt, VkSpace);
        return registered;
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == WmHotKey && message.WParam.ToInt32() == HotKeyId)
            action();
        base.WndProc(ref message);
    }

    public void Dispose()
    {
        if (registered)
            UnregisterHotKey(Handle, HotKeyId);
        DestroyHandle();
    }

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
