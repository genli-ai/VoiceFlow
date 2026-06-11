using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;

namespace MicType.Win.Core;

public sealed class AppSettings
{
    public AppLanguage AppLanguage { get; set; } = CultureDefaultLanguage();
    public HotkeyChoice Hotkey { get; set; } = HotkeyChoice.RightControl;
    public bool PlaySounds { get; set; } = true;
    public bool RestoreClipboard { get; set; } = true;
    public bool LaunchAtLogin { get; set; }

    public string SpeechModelRepo { get; set; } = "sherpa-onnx/SenseVoiceSmall";
    public string CustomVocabulary { get; set; } = "";

    public PolishLevel PolishLevel { get; set; } = PolishLevel.Smart;
    public LlmProvider LlmProvider { get; set; } = LlmProvider.OpenAi;
    public string OpenAiBaseUrl { get; set; } = "https://api.openai.com/v1";
    public string DeepSeekBaseUrl { get; set; } = "https://api.deepseek.com";
    public string OpenAiPolishModel { get; set; } = "gpt-5.4-nano";
    public string OpenAiCommandModel { get; set; } = "gpt-5.4-mini";
    public string DeepSeekPolishModel { get; set; } = "deepseek-v4-flash";
    public string DeepSeekCommandModel { get; set; } = "deepseek-v4-flash";
    public double PolishTemperature { get; set; } = 0.5;
    public double CommandTemperature { get; set; } = 1.0;
    public string AboutMe { get; set; } = "";
    public string CustomPolishRules { get; set; } = "";

    [JsonIgnore]
    public string CurrentBaseUrl => LlmProvider == LlmProvider.OpenAi ? OpenAiBaseUrl : DeepSeekBaseUrl;

    [JsonIgnore]
    public string CurrentPolishModel => LlmProvider == LlmProvider.OpenAi ? OpenAiPolishModel : DeepSeekPolishModel;

    [JsonIgnore]
    public string CurrentCommandModel => LlmProvider == LlmProvider.OpenAi ? OpenAiCommandModel : DeepSeekCommandModel;

    [JsonIgnore]
    public string CurrentCredentialTarget =>
        LlmProvider == LlmProvider.OpenAi ? CredentialTargets.OpenAiApiKey : CredentialTargets.DeepSeekApiKey;

    [JsonIgnore]
    public IReadOnlyList<string> VocabularyTerms => ParseVocabulary(CustomVocabulary).Terms;

    [JsonIgnore]
    public IReadOnlyList<(string Wrong, string Right)> VocabularyReplacements =>
        ParseVocabulary(CustomVocabulary).Replacements;

    public static (IReadOnlyList<string> Terms, IReadOnlyList<(string Wrong, string Right)> Replacements)
        ParseVocabulary(string value)
    {
        var terms = new List<string>();
        var replacements = new List<(string Wrong, string Right)>();
        foreach (var raw in value.Split([',', '，', '、', '\n', '\r'],
                     StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            var entry = raw.Replace('＝', '=').Trim();
            var equalsIndex = entry.IndexOf('=');
            if (equalsIndex >= 0)
            {
                var wrong = entry[..equalsIndex].Trim();
                var right = entry[(equalsIndex + 1)..].Trim();
                if (wrong.Length == 0 || right.Length == 0) continue;
                replacements.Add((wrong, right));
                terms.Add(right);
            }
            else if (entry.Length > 0)
            {
                terms.Add(entry);
            }
        }

        return (terms, replacements);
    }

    private static AppLanguage CultureDefaultLanguage()
    {
        var name = Thread.CurrentThread.CurrentUICulture.Name;
        return name.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? AppLanguage.Zh : AppLanguage.En;
    }
}

public static class CredentialTargets
{
    public const string OpenAiApiKey = "MicType/openai_api_key";
    public const string DeepSeekApiKey = "MicType/deepseek_api_key";
}

public sealed class SettingsStore
{
    public static SettingsStore Instance { get; } = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters =
        {
            new HotkeyChoiceJsonConverter(),
            new JsonStringEnumConverter()
        }
    };

    private SettingsStore()
    {
        Current = Load();
    }

    public AppSettings Current { get; private set; }

    public void Save()
    {
        Directory.CreateDirectory(AppPaths.AppDataDir);
        var json = JsonSerializer.Serialize(Current, JsonOptions);
        File.WriteAllText(AppPaths.SettingsPath, json);
    }

    public void Reload()
    {
        Current = Load();
    }

    private static AppSettings Load()
    {
        try
        {
            if (!File.Exists(AppPaths.SettingsPath))
            {
                var fresh = new AppSettings();
                File.WriteAllText(AppPaths.SettingsPath, JsonSerializer.Serialize(fresh, JsonOptions));
                return fresh;
            }

            var json = File.ReadAllText(AppPaths.SettingsPath);
            return JsonSerializer.Deserialize<AppSettings>(json, JsonOptions) ?? new AppSettings();
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Failed to load settings");
            return new AppSettings();
        }
    }
}

public sealed class HotkeyChoiceJsonConverter : JsonConverter<HotkeyChoice>
{
    public override HotkeyChoice Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var value = reader.TokenType == JsonTokenType.String ? reader.GetString() : null;
        return value switch
        {
            nameof(HotkeyChoice.RightShift) => HotkeyChoice.RightShift,
            _ => HotkeyChoice.RightControl
        };
    }

    public override void Write(Utf8JsonWriter writer, HotkeyChoice value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value.ToString());
    }
}
