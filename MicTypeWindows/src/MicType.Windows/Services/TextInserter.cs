using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using MicType.Win.Core;

namespace MicType.Win.Services;

public enum InsertOutcome
{
    Pasted,
    ClipboardOnly,
    Timeout,
    Error
}

public sealed record InsertResult(InsertOutcome Outcome, bool ClipboardReady, string? Error = null);

public static class TextInserter
{
    private static readonly StaWorker Worker = new("MicType Clipboard STA");
    private static readonly TimeSpan InsertTimeout = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan ClipboardTimeout = TimeSpan.FromMilliseconds(750);

    public static IntPtr CaptureForegroundWindow() => GetForegroundWindow();

    public static async Task<InsertResult> InsertAsync(
        string text,
        IntPtr targetWindow,
        string? targetProcessName = null,
        bool allowClipboardRestore = true,
        bool conservativePaste = false)
    {
        Log.Info(
            "Insert begin " +
            $"targetWindow=0x{targetWindow.ToInt64():X} targetProcess={targetProcessName ?? "unknown"} chars={text.Length}");

        var operation = Worker.InvokeAsync(() =>
            InsertCore(text, targetWindow, targetProcessName, allowClipboardRestore, conservativePaste));
        var completed = await Task.WhenAny(operation, Task.Delay(InsertTimeout));
        if (completed == operation)
        {
            return await operation;
        }

        Log.Warn("Insert timeout; paste abandoned after 5s");
        _ = operation.ContinueWith(
            task => Log.Error(task.Exception!, "Timed-out insert later failed"),
            TaskContinuationOptions.OnlyOnFaulted);
        var clipboardReady = await TrySetClipboardTextOnTemporaryStaAsync(text, TimeSpan.FromSeconds(1));
        Log.Warn($"Insert timeout fallback clipboardReady={clipboardReady}");
        return new InsertResult(InsertOutcome.Timeout, clipboardReady, "Insert timed out");
    }

    public static async Task<bool> SetClipboardTextAsync(string text)
    {
        var result = await Worker.InvokeAsync(() => TrySetClipboardText(text, ClipboardTimeout));
        Log.Info($"Clipboard write text chars={text.Length} ok={result}");
        return result;
    }

    public static Task<string?> GetClipboardTextAsync()
    {
        return Worker.InvokeAsync(() => TryGetClipboardText(ClipboardTimeout));
    }

    public static async Task<bool> ClearClipboardAsync()
    {
        var result = await Worker.InvokeAsync(() => TrySetClipboardText(null, ClipboardTimeout));
        Log.Info($"Clipboard clear ok={result}");
        return result;
    }

    internal static void SendCtrlC()
    {
        Worker.Post(() =>
        {
            Log.Info("SendInput Ctrl+C");
            SendModifiedKey(0x11, 0x43, 30);
        });
    }

    private static InsertResult InsertCore(
        string text,
        IntPtr targetWindow,
        string? targetProcessName,
        bool allowClipboardRestore,
        bool conservativePaste)
    {
        try
        {
            if (targetWindow != IntPtr.Zero && GetForegroundWindow() != targetWindow)
            {
                Log.Info(
                    "Insert focus switch " +
                    $"targetWindow=0x{targetWindow.ToInt64():X} targetProcess={targetProcessName ?? "unknown"}");
                var focused = SetForegroundWindow(targetWindow);
                Log.Info($"Insert focus SetForegroundWindow result={focused}");
                Thread.Sleep(conservativePaste ? 750 : 250);
            }

            var oldText = TryGetClipboardText(ClipboardTimeout);
            var clipboardReady = TrySetClipboardText(text, ClipboardTimeout);
            Log.Info($"Insert clipboard write result={clipboardReady} chars={text.Length}");
            if (!clipboardReady)
            {
                return new InsertResult(InsertOutcome.Error, ClipboardReady: false, Error: "Could not write clipboard");
            }

            if (targetWindow != IntPtr.Zero && GetForegroundWindow() != targetWindow)
            {
                Log.Warn($"Insert clipboard fallback; foreground did not return to target=0x{targetWindow.ToInt64():X}");
                return new InsertResult(InsertOutcome.ClipboardOnly, ClipboardReady: true);
            }

            Thread.Sleep(conservativePaste ? 350 : 180);
            Log.Info("Insert SendInput Ctrl+V");
            if (!SendCtrlV(conservativePaste ? 120 : 30))
            {
                // 粘贴按键没发出去：文本还在剪贴板，降级提示用户手动 Ctrl+V（此时绝不能恢复旧剪贴板）
                Log.Warn("Insert clipboard fallback; SendInput rejected the paste keystrokes");
                return new InsertResult(InsertOutcome.ClipboardOnly, ClipboardReady: true);
            }

            if (allowClipboardRestore && SettingsStore.Instance.Current.RestoreClipboard)
            {
                ScheduleClipboardRestore(text, oldText);
            }

            Log.Info($"Insert end outcome=Pasted chars={text.Length}");
            return new InsertResult(InsertOutcome.Pasted, ClipboardReady: true);
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Insert failed");
            return new InsertResult(InsertOutcome.Error, ClipboardReady: false, Error: ex.Message);
        }
    }

    private static void ScheduleClipboardRestore(string ourText, string? oldText)
    {
        _ = Task.Run(async () =>
        {
            await Task.Delay(TimeSpan.FromSeconds(5));
            await Worker.InvokeAsync(() =>
            {
                var current = TryGetClipboardText(ClipboardTimeout);
                if (current != ourText) return;

                var restored = TrySetClipboardText(oldText, ClipboardTimeout);
                Log.Info(oldText is null
                    ? $"Clipboard restored by clearing MicType text ok={restored}"
                    : $"Clipboard restored to previous text ok={restored}");
            });
        });
    }

    private static bool TrySetClipboardText(string? text, TimeSpan timeout)
    {
        var deadline = DateTimeOffset.UtcNow + timeout;
        do
        {
            if (OpenClipboard(IntPtr.Zero))
            {
                try
                {
                    EmptyClipboard();
                    if (text is null)
                    {
                        return true;
                    }

                    var bytes = (text.Length + 1) * 2;
                    var handle = GlobalAlloc(GmemMoveable, (UIntPtr)bytes);
                    if (handle == IntPtr.Zero) return false;

                    var locked = GlobalLock(handle);
                    if (locked == IntPtr.Zero)
                    {
                        GlobalFree(handle);
                        return false;
                    }

                    try
                    {
                        Marshal.Copy(text.ToCharArray(), 0, locked, text.Length);
                        Marshal.WriteInt16(locked, text.Length * 2, 0);
                    }
                    finally
                    {
                        GlobalUnlock(handle);
                    }

                    if (SetClipboardData(CfUnicodeText, handle) == IntPtr.Zero)
                    {
                        GlobalFree(handle);
                        return false;
                    }

                    return true;
                }
                finally
                {
                    CloseClipboard();
                }
            }

            Thread.Sleep(35);
        } while (DateTimeOffset.UtcNow < deadline);

        Log.Warn("Clipboard write timed out waiting for OpenClipboard");
        return false;
    }

    private static async Task<bool> TrySetClipboardTextOnTemporaryStaAsync(string text, TimeSpan timeout)
    {
        var tcs = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try
            {
                tcs.SetResult(TrySetClipboardText(text, timeout));
            }
            catch (Exception ex)
            {
                tcs.SetException(ex);
            }
        })
        {
            IsBackground = true,
            Name = "MicType Clipboard Timeout Fallback"
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();

        var completed = await Task.WhenAny(tcs.Task, Task.Delay(timeout + TimeSpan.FromMilliseconds(250)));
        if (completed != tcs.Task)
        {
            Log.Warn("Temporary STA clipboard write timed out");
            return false;
        }

        return await tcs.Task;
    }

    private static string? TryGetClipboardText(TimeSpan timeout)
    {
        var deadline = DateTimeOffset.UtcNow + timeout;
        do
        {
            if (OpenClipboard(IntPtr.Zero))
            {
                try
                {
                    if (!IsClipboardFormatAvailable(CfUnicodeText)) return null;
                    var handle = GetClipboardData(CfUnicodeText);
                    if (handle == IntPtr.Zero) return null;
                    var locked = GlobalLock(handle);
                    if (locked == IntPtr.Zero) return null;
                    try
                    {
                        return Marshal.PtrToStringUni(locked);
                    }
                    finally
                    {
                        GlobalUnlock(handle);
                    }
                }
                finally
                {
                    CloseClipboard();
                }
            }

            Thread.Sleep(35);
        } while (DateTimeOffset.UtcNow < deadline);

        Log.Warn("Clipboard read timed out waiting for OpenClipboard");
        return null;
    }

    private static bool SendCtrlV(int holdMilliseconds)
    {
        return SendModifiedKey(0x11, 0x56, holdMilliseconds);
    }

    private static bool SendModifiedKey(ushort modifier, ushort key, int holdMilliseconds)
    {
        var inputs = new[]
        {
            KeyboardInput(modifier, false),
            KeyboardInput(key, false),
            KeyboardInput(key, true),
            KeyboardInput(modifier, true)
        };
        var sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>());
        if (sent != inputs.Length)
        {
            Log.Warn($"SendInput key=0x{key:X} sent={sent}/{inputs.Length} lastError={Marshal.GetLastWin32Error()}");
            return false;
        }

        Log.Info($"SendInput key=0x{key:X} sent={sent}/{inputs.Length}");
        if (holdMilliseconds > 30)
        {
            Thread.Sleep(holdMilliseconds);
        }
        return true;
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

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EmptyClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetClipboardData(uint uFormat);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool IsClipboardFormatAvailable(uint format);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalUnlock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalFree(IntPtr hMem);

    private const uint CfUnicodeText = 13;
    private const uint GmemMoveable = 0x0002;

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        // MOUSEINPUT 是 union 里最大的成员——没有它 INPUT 在 x64 上只有 32 字节而系统要求 40，
        // SendInput 会拒收全部输入并返回 0（真机三轮 "sent=0/4" 的根因）
        [FieldOffset(0)] public MouseInputStruct Mi;
        [FieldOffset(0)] public KeyboardInputStruct Ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInputStruct
    {
        public int Dx;
        public int Dy;
        public uint MouseData;
        public uint DwFlags;
        public uint Time;
        public IntPtr DwExtraInfo;
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

    private sealed class StaWorker
    {
        private readonly BlockingCollection<Action> _queue = new();

        public StaWorker(string name)
        {
            var thread = new Thread(Run)
            {
                IsBackground = true,
                Name = name
            };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
        }

        public Task InvokeAsync(Action action)
        {
            var tcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            _queue.Add(() =>
            {
                try
                {
                    action();
                    tcs.SetResult();
                }
                catch (Exception ex)
                {
                    tcs.SetException(ex);
                }
            });
            return tcs.Task;
        }

        public Task<T> InvokeAsync<T>(Func<T> func)
        {
            var tcs = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
            _queue.Add(() =>
            {
                try
                {
                    tcs.SetResult(func());
                }
                catch (Exception ex)
                {
                    tcs.SetException(ex);
                }
            });
            return tcs.Task;
        }

        public void Post(Action action)
        {
            _queue.Add(() =>
            {
                try
                {
                    action();
                }
                catch (Exception ex)
                {
                    Log.Error(ex, "STA worker posted action failed");
                }
            });
        }

        private void Run()
        {
            foreach (var action in _queue.GetConsumingEnumerable())
            {
                action();
            }
        }
    }
}
