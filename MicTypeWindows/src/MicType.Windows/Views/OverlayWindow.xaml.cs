using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using MicType.Win.Core;
using Forms = System.Windows.Forms;

namespace MicType.Win.Views;

public partial class OverlayWindow : Window
{
    private int _generation;

    public OverlayWindow()
    {
        InitializeComponent();
    }

    public void ShowRecording(string label)
    {
        _generation++;
        Spinner.Visibility = Visibility.Collapsed;
        Dot.Visibility = Visibility.Visible;
        Dot.Fill = new SolidColorBrush(Color.FromRgb(248, 113, 113));
        MessageText.Text = label;
        Position();
        Show();
    }

    public void ShowProcessing(string label)
    {
        _generation++;
        Dot.Visibility = Visibility.Collapsed;
        Spinner.Visibility = Visibility.Visible;
        MessageText.Text = label;
        Position();
        Show();
    }

    public void FlashSuccess(string label)
    {
        Flash(label, Color.FromRgb(34, 197, 94), TimeSpan.FromSeconds(1));
    }

    public void FlashError(string label)
    {
        Flash(label, Color.FromRgb(250, 204, 21), TimeSpan.FromSeconds(2.5));
    }

    private void Flash(string label, Color color, TimeSpan duration)
    {
        _generation++;
        var generation = _generation;
        Spinner.Visibility = Visibility.Collapsed;
        Dot.Visibility = Visibility.Visible;
        Dot.Fill = new SolidColorBrush(color);
        MessageText.Text = label;
        Position();
        Show();
        var timer = new DispatcherTimer { Interval = duration };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (_generation == generation) Hide();
        };
        timer.Start();
    }

    private void Position()
    {
        var cursor = Forms.Cursor.Position;
        var screen = Forms.Screen.FromPoint(cursor);
        var area = screen.WorkingArea;
        var scale = WindowsDpi.ScaleForPoint(cursor.X, cursor.Y);
        var placement = OverlayPlacement.Calculate(
            new PhysicalRect(area.Left, area.Top, area.Width, area.Height),
            ActualWidth > 0 ? ActualWidth : Width,
            ActualHeight > 0 ? ActualHeight : Height,
            scale);

        var hwnd = new WindowInteropHelper(this).EnsureHandle();
        SetWindowPos(
            hwnd,
            HwndTopmost,
            placement.X,
            placement.Y,
            0,
            0,
            SetWindowPosFlags.NoSize | SetWindowPosFlags.NoActivate);

        Log.Info(
            "Overlay position " +
            $"screen={screen.DeviceName} primary={screen.Primary} scale={placement.Scale:0.###} " +
            $"workAreaPx=({area.Left},{area.Top},{area.Width},{area.Height}) " +
            $"sizePx=({placement.WidthPx},{placement.HeightPx}) " +
            $"targetPx=({placement.X},{placement.Y}) targetDip=({placement.DipX:0.##},{placement.DipY:0.##})");
    }

    private static readonly IntPtr HwndTopmost = new(-1);

    [Flags]
    private enum SetWindowPosFlags : uint
    {
        NoSize = 0x0001,
        NoActivate = 0x0010
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int x,
        int y,
        int cx,
        int cy,
        SetWindowPosFlags flags);
}
