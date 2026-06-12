using System.Diagnostics;
using System.Windows;
using Forms = System.Windows.Forms;
using Drawing = System.Drawing;
using MicType.Win.Core;
using MicType.Win.Services;
using MicType.Win.Views;

namespace MicType.Win;

public partial class App : Application
{
    private Forms.NotifyIcon? _tray;
    private DictationController? _dictation;
    private GlobalHotkeyManager? _hotkeys;
    private OverlayWindow? _overlay;
    private SettingsWindow? _settingsWindow;
    private ISpeechEngine? _speechEngine;

    private Mutex? _singleInstanceMutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        _singleInstanceMutex = new Mutex(true, "MicTypeWindowsSingleInstance", out var isFirstInstance);
        if (!isFirstInstance)
        {
            MessageBox.Show(
                L10n.Tr("MicType 已经在运行（看系统托盘右下角）。", "MicType is already running (check the system tray)."),
                "MicType");
            Shutdown();
            return;
        }

        Log.Initialize();
        base.OnStartup(e);
        DispatcherUnhandledException += (_, args) =>
        {
            Log.Error(args.Exception, "Unhandled dispatcher exception");
        };

        _overlay = new OverlayWindow();
        _speechEngine = new SenseVoiceSpeechEngine();
        Log.Startup(SettingsStore.Instance.Current, _speechEngine.EngineName, _speechEngine.IsModelAvailable);
        _dictation = new DictationController(_speechEngine, _overlay);
        _speechEngine.Preload();
        _hotkeys = new GlobalHotkeyManager
        {
            IsRecording = () => _dictation?.IsRecording == true
        };
        _hotkeys.TapToggle += () => Dispatcher.BeginInvoke(() =>
        {
            Log.Info("Hotkey tap");
            _dictation.Toggle();
        });
        _hotkeys.SkillStart += () => Dispatcher.BeginInvoke(() =>
        {
            Log.Info("Hotkey hold-start");
            _dictation.SkillHoldStart();
        });
        _hotkeys.SkillEnd += () => Dispatcher.BeginInvoke(() =>
        {
            Log.Info("Hotkey hold-end");
            _dictation.SkillHoldEnd();
        });
        _hotkeys.Cancel += () => Dispatcher.BeginInvoke(() =>
        {
            Log.Info("Hotkey Esc cancel");
            _dictation.Cancel();
        });
        _hotkeys.Start();
        Log.Info("Global hotkeys started");

        _dictation.NeedSettings += ShowSettings;
        _dictation.PhaseChanged += _ => UpdateTrayText();

        CreateTray();
        UpdateTrayText();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkeys?.Dispose();
        _speechEngine?.UnloadModel();
        _tray?.Dispose();
        base.OnExit(e);
    }

    private void CreateTray()
    {
        _tray = new Forms.NotifyIcon
        {
            Icon = Drawing.SystemIcons.Application,
            Visible = true,
            Text = "MicType"
        };
        _tray.DoubleClick += (_, _) => _dictation?.Toggle();
        _tray.ContextMenuStrip = new Forms.ContextMenuStrip();
        PopulateMenu(_tray.ContextMenuStrip);
        _tray.ContextMenuStrip.Opening += (_, _) =>
        {
            if (_tray?.ContextMenuStrip is not null) PopulateMenu(_tray.ContextMenuStrip);
        };
    }

    private void PopulateMenu(Forms.ContextMenuStrip menu)
    {
        menu.Items.Clear();
        var hotkey = SettingsStore.Instance.Current.Hotkey switch
        {
            HotkeyChoice.RightShift => "Right Shift",
            _ => "Right Ctrl"
        };
        menu.Items.Add(new Forms.ToolStripLabel(
            L10n.Tr($"轻点 {hotkey} 听写 · 按住说指令", $"Tap {hotkey} to dictate · hold for commands")));

        if (_dictation?.Phase == Phase.Recording)
        {
            menu.Items.Add(L10n.Tr("停止并输出", "Stop & Insert"), null, (_, _) => _dictation.Toggle());
            menu.Items.Add(L10n.Tr("取消录音（Esc）", "Cancel Recording (Esc)"), null, (_, _) => _dictation.Cancel());
        }
        else if (_dictation?.Phase == Phase.Processing)
        {
            menu.Items.Add(new Forms.ToolStripLabel(L10n.Tr("处理中…", "Processing…")));
        }
        else
        {
            menu.Items.Add(L10n.Tr("开始听写", "Start Dictation"), null, (_, _) => _dictation?.Toggle());
        }

        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(L10n.Tr("仅识别", "Transcribe only"), null, (_, _) =>
        {
            SettingsStore.Instance.Current.PolishLevel = PolishLevel.Off;
            SettingsStore.Instance.Save();
        });
        menu.Items.Add(L10n.Tr("AI 润色", "AI polish"), null, (_, _) =>
        {
            SettingsStore.Instance.Current.PolishLevel = PolishLevel.Smart;
            SettingsStore.Instance.Save();
        });

        var history = new Forms.ToolStripMenuItem(L10n.Tr("最近记录", "Recent Transcripts"));
        if (HistoryStore.Instance.Items.Count == 0)
        {
            history.DropDownItems.Add(new Forms.ToolStripLabel(L10n.Tr("（暂无）", "(empty)")));
        }
        else
        {
            foreach (var item in HistoryStore.Instance.Items.Take(10))
            {
                var title = item.Polished.ReplaceLineEndings(" ");
                if (title.Length > 36) title = title[..36] + "...";
                history.DropDownItems.Add(title, null, (_, _) => _ = TextInserter.SetClipboardTextAsync(item.Polished));
            }
            history.DropDownItems.Add(new Forms.ToolStripSeparator());
            history.DropDownItems.Add(L10n.Tr("清空记录", "Clear History"), null, (_, _) => HistoryStore.Instance.Clear());
        }
        menu.Items.Add(history);

        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(L10n.Tr("设置…", "Settings…"), null, (_, _) => ShowSettings());
        menu.Items.Add(L10n.Tr("打开日志文件夹", "Open Logs Folder"), null, (_, _) => OpenLogsFolder());
        menu.Items.Add(L10n.Tr("退出 MicType", "Quit MicType"), null, (_, _) => Shutdown());
    }

    private static void OpenLogsFolder()
    {
        try
        {
            Log.Info("Open logs folder");
            Process.Start(new ProcessStartInfo("explorer.exe", $"\"{Log.LogsDir}\"")
            {
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Failed to open logs folder");
        }
    }

    private void ShowSettings()
    {
        Dispatcher.BeginInvoke(() =>
        {
            if (_settingsWindow is null)
            {
                _settingsWindow = new SettingsWindow();
                _settingsWindow.Closed += (_, _) => _settingsWindow = null;
            }
            _settingsWindow.Show();
            _settingsWindow.Activate();
        });
    }

    private void UpdateTrayText()
    {
        if (_tray is null || _dictation is null) return;
        _tray.Text = _dictation.Phase switch
        {
            Phase.Recording => L10n.Tr("MicType - 录音中", "MicType - Recording"),
            Phase.Processing => L10n.Tr("MicType - 处理中", "MicType - Processing"),
            _ => "MicType"
        };
    }
}
