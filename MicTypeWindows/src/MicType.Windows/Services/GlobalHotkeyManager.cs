using System.Diagnostics;
using System.Runtime.InteropServices;
using MicType.Win.Core;

namespace MicType.Win.Services;

public sealed class GlobalHotkeyManager : IDisposable
{
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;
    private const int VkEscape = 0x1B;

    private readonly LowLevelKeyboardProc _proc;
    private IntPtr _hookId;
    private readonly HashSet<int> _pressedKeys = [];
    private DateTimeOffset? _pressedAt;
    private bool _tapCandidate;
    private bool _skillActive;
    private System.Threading.Timer? _holdTimer;

    public GlobalHotkeyManager()
    {
        _proc = HookCallback;
    }

    public event Action? TapToggle;
    public event Action? SkillStart;
    public event Action? SkillEnd;
    public event Action? Cancel;
    public Func<bool> IsRecording { get; set; } = () => false;

    public void Start()
    {
        Stop();
        using var process = Process.GetCurrentProcess();
        using var module = process.MainModule;
        _hookId = SetWindowsHookEx(WhKeyboardLl, _proc, GetModuleHandle(module?.ModuleName), 0);
    }

    public void Stop()
    {
        if (_hookId != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hookId);
            _hookId = IntPtr.Zero;
        }
        _holdTimer?.Dispose();
        _holdTimer = null;
    }

    public void Dispose() => Stop();

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0) return CallNextHookEx(_hookId, nCode, wParam, lParam);

        var info = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);
        var vkCode = (int)info.VkCode;
        var isDown = wParam == WmKeyDown || wParam == WmSysKeyDown;
        var isUp = wParam == WmKeyUp || wParam == WmSysKeyUp;

        if (isDown && vkCode == VkEscape && IsRecording())
        {
            Cancel?.Invoke();
            return 1; // recording mode swallows Esc
        }

        var target = TargetVirtualKey(SettingsStore.Instance.Current.Hotkey);
        if (isDown)
        {
            var wasAlreadyDown = !_pressedKeys.Add(vkCode);
            if (vkCode == target && !wasAlreadyDown && _pressedKeys.Count == 1)
            {
                BeginTapCandidate();
            }
            else if (vkCode != target)
            {
                CancelTapCandidate();
            }
        }
        else if (isUp)
        {
            _pressedKeys.Remove(vkCode);
            if (vkCode == target)
            {
                EndTargetKey();
            }
        }

        return CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    private void BeginTapCandidate()
    {
        _tapCandidate = true;
        _pressedAt = DateTimeOffset.Now;
        _skillActive = false;
        _holdTimer?.Dispose();
        _holdTimer = new System.Threading.Timer(_ =>
        {
            if (!_tapCandidate || IsRecording()) return;
            _skillActive = true;
            SkillStart?.Invoke();
        }, null, TimeSpan.FromMilliseconds(600), Timeout.InfiniteTimeSpan);
    }

    private void EndTargetKey()
    {
        _holdTimer?.Dispose();
        _holdTimer = null;
        if (_skillActive)
        {
            _skillActive = false;
            SkillEnd?.Invoke();
        }
        else if (_tapCandidate && IsRecording())
        {
            TapToggle?.Invoke();
        }
        else if (_tapCandidate && _pressedAt is { } t &&
                 DateTimeOffset.Now - t < TimeSpan.FromMilliseconds(600))
        {
            TapToggle?.Invoke();
        }

        _tapCandidate = false;
        _pressedAt = null;
    }

    private void CancelTapCandidate()
    {
        _tapCandidate = false;
        _holdTimer?.Dispose();
        _holdTimer = null;
    }

    private static int TargetVirtualKey(HotkeyChoice choice) => choice switch
    {
        HotkeyChoice.RightControl => 0xA3,
        HotkeyChoice.RightShift => 0xA1,
        _ => 0xA3
    };

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KbdLlHookStruct
    {
        public uint VkCode;
        public uint ScanCode;
        public uint Flags;
        public uint Time;
        public IntPtr DwExtraInfo;
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);
}
