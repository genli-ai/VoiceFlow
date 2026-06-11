using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;
using MicType.Win.Core;

namespace MicType.Win.Services;

public enum InsertOutcome
{
    Pasted,
    ClipboardOnly
}

public static class TextInserter
{
    public static IntPtr CaptureForegroundWindow() => GetForegroundWindow();

    public static async Task<InsertOutcome> InsertAsync(
        string text,
        IntPtr targetWindow,
        bool allowClipboardRestore = true,
        bool conservativePaste = false)
    {
        if (targetWindow != IntPtr.Zero && GetForegroundWindow() != targetWindow)
        {
            Log.Info($"Insert target window is not foreground; attempting focus target=0x{targetWindow.ToInt64():X}");
            SetForegroundWindow(targetWindow);
            await Task.Delay(conservativePaste ? 750 : 250);
        }

        if (targetWindow != IntPtr.Zero && GetForegroundWindow() != targetWindow)
        {
            Log.Warn($"Insert fallback to clipboard; foreground did not return to target=0x{targetWindow.ToInt64():X}");
            SetClipboardText(text);
            return InsertOutcome.ClipboardOnly;
        }

        var oldText = GetClipboardText();
        SetClipboardText(text);
        await Task.Delay(conservativePaste ? 350 : 180);
        SendCtrlV(conservativePaste ? 120 : 30);

        if (allowClipboardRestore && SettingsStore.Instance.Current.RestoreClipboard)
        {
            _ = RestoreClipboardLater(text, oldText);
        }

        Log.Info($"Insert pasted chars={text.Length} restoreClipboard={allowClipboardRestore && SettingsStore.Instance.Current.RestoreClipboard}");
        return InsertOutcome.Pasted;
    }

    public static void SetClipboardText(string text)
    {
        Application.Current.Dispatcher.Invoke(() => Clipboard.SetText(text));
    }

    public static string? GetClipboardText()
    {
        return Application.Current.Dispatcher.Invoke(() =>
            Clipboard.ContainsText() ? Clipboard.GetText() : null);
    }

    private static async Task RestoreClipboardLater(string ourText, string? oldText)
    {
        await Task.Delay(TimeSpan.FromSeconds(5));
        Application.Current.Dispatcher.Invoke(() =>
        {
            if (!Clipboard.ContainsText() || Clipboard.GetText() != ourText) return;
            if (oldText is null)
            {
                Clipboard.Clear();
                Log.Info("Clipboard restored by clearing MicType text");
            }
            else
            {
                Clipboard.SetText(oldText);
                Log.Info("Clipboard restored to previous text");
            }
        }, DispatcherPriority.Background);
    }

    private static void SendCtrlV(int holdMilliseconds)
    {
        SendModifiedKey(0x11, 0x56, holdMilliseconds);
    }

    internal static void SendCtrlC()
    {
        SendModifiedKey(0x11, 0x43, 30);
    }

    private static void SendModifiedKey(ushort modifier, ushort key, int holdMilliseconds)
    {
        var inputs = new[]
        {
            KeyboardInput(modifier, false),
            KeyboardInput(key, false),
            KeyboardInput(key, true),
            KeyboardInput(modifier, true)
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>());
        if (holdMilliseconds > 30)
        {
            Thread.Sleep(holdMilliseconds);
        }
    }

    private static Input KeyboardInput(ushort key, bool keyUp) => new()
    {
        Type = 1,
        U = new InputUnion
        {
            Ki = new KeyboardInputStruct
            {
                WVk = key,
                DwFlags = keyUp ? 0x0002u : 0
            }
        }
    };

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, Input[] pInputs, int cbSize);

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public KeyboardInputStruct Ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInputStruct
    {
        public ushort WVk;
        public ushort WScan;
        public uint DwFlags;
        public uint Time;
        public IntPtr DwExtraInfo;
    }
}
