using System.Diagnostics;
using System.IO;

namespace MicType.Win.Core;

public static class Log
{
    private static readonly object Gate = new();
    private static Func<DateTimeOffset> _clock = () => DateTimeOffset.Now;
    private static string? _logsDir;

    public static string LogsDir
    {
        get
        {
            var dir = _logsDir ?? AppPaths.LogsDir;
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string CurrentLogPath => Path.Combine(LogsDir, $"mictype-{_clock().LocalDateTime:yyyyMMdd}.log");

    public static void Initialize(string? logsDir = null, Func<DateTimeOffset>? clock = null)
    {
        lock (Gate)
        {
            _logsDir = logsDir;
            _clock = clock ?? (() => DateTimeOffset.Now);
            Directory.CreateDirectory(LogsDir);
            CleanupOldLogsLocked();
        }

        Info("Log initialized");
    }

    public static void Info(string message) => Write("INFO", message);

    public static void Warn(string message) => Write("WARN", message);

    public static void Error(Exception ex, string message)
    {
        Write("ERROR", $"{message}{Environment.NewLine}{ex}");
    }

    public static void Startup(AppSettings settings, string engineName, bool modelAvailable)
    {
        var assembly = typeof(Log).Assembly.GetName();
        Info($"Startup version={assembly.Version} os={Environment.OSVersion.VersionString} process={Process.GetCurrentProcess().ProcessName}");
        Info(
            "Settings " +
            $"language={settings.AppLanguage} hotkey={settings.Hotkey} polish={settings.PolishLevel} " +
            $"provider={settings.LlmProvider} playSounds={settings.PlaySounds} restoreClipboard={settings.RestoreClipboard} " +
            $"engine={engineName} modelAvailable={modelAvailable} " +
            $"vocabularyTerms={settings.VocabularyTerms.Count} replacements={settings.VocabularyReplacements.Count}");
        try
        {
            var hasOpenAi = Services.CredentialStore.Load(CredentialTargets.OpenAiApiKey) is not null;
            var hasDeepSeek = Services.CredentialStore.Load(CredentialTargets.DeepSeekApiKey) is not null;
            Info($"Credentials openAiKey={hasOpenAi} deepSeekKey={hasDeepSeek}");
        }
        catch (Exception ex)
        {
            Warn("Credential presence check failed: " + ex.Message);
        }
        foreach (var display in WindowsDpi.DescribeDisplays())
        {
            Info("Display " + display);
        }
    }

    private static void Write(string level, string message)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(LogsDir);
                var line = $"{_clock():O} [{level}] {message}{Environment.NewLine}";
                File.AppendAllText(CurrentLogPath, line);
            }
        }
        catch
        {
            // Logging must never break dictation.
        }
    }

    private static void CleanupOldLogsLocked()
    {
        var cutoff = _clock().LocalDateTime.Date.AddDays(-7);
        foreach (var file in Directory.EnumerateFiles(LogsDir, "mictype-*.log"))
        {
            var name = Path.GetFileNameWithoutExtension(file);
            if (name.Length != "mictype-yyyyMMdd".Length ||
                !DateTime.TryParseExact(
                    name["mictype-".Length..],
                    "yyyyMMdd",
                    null,
                    System.Globalization.DateTimeStyles.None,
                    out var date) ||
                date >= cutoff)
            {
                continue;
            }

            try
            {
                File.Delete(file);
            }
            catch
            {
                // Best-effort cleanup only.
            }
        }
    }
}
