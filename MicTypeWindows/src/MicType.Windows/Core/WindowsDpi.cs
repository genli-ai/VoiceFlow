using System.Runtime.InteropServices;
using Forms = System.Windows.Forms;

namespace MicType.Win.Core;

public static class WindowsDpi
{
    private const int MonitorDefaultToNearest = 2;

    public static double ScaleForPoint(int x, int y)
    {
        try
        {
            var monitor = MonitorFromPoint(new PointStruct(x, y), MonitorDefaultToNearest);
            if (monitor != IntPtr.Zero &&
                GetDpiForMonitor(monitor, MonitorDpiType.Effective, out var dpiX, out _) == 0 &&
                dpiX > 0)
            {
                return dpiX / 96.0;
            }
        }
        catch (DllNotFoundException ex)
        {
            Log.Error(ex, "GetDpiForMonitor unavailable");
        }
        catch (EntryPointNotFoundException ex)
        {
            Log.Error(ex, "GetDpiForMonitor entry point unavailable");
        }

        using var graphics = System.Drawing.Graphics.FromHwnd(IntPtr.Zero);
        return graphics.DpiX / 96.0;
    }

    public static IEnumerable<string> DescribeDisplays()
    {
        foreach (var screen in Forms.Screen.AllScreens)
        {
            var bounds = screen.Bounds;
            var area = screen.WorkingArea;
            var scale = ScaleForPoint(bounds.Left + Math.Max(1, bounds.Width / 2), bounds.Top + Math.Max(1, bounds.Height / 2));
            yield return
                $"device={screen.DeviceName} primary={screen.Primary} scale={scale:0.###} " +
                $"bounds=({bounds.Left},{bounds.Top},{bounds.Width},{bounds.Height}) " +
                $"workArea=({area.Left},{area.Top},{area.Width},{area.Height})";
        }
    }

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(PointStruct pt, int flags);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr hmonitor, MonitorDpiType dpiType, out uint dpiX, out uint dpiY);

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct PointStruct(int x, int y)
    {
        public readonly int X = x;
        public readonly int Y = y;
    }

    private enum MonitorDpiType
    {
        Effective = 0
    }
}
