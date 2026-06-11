namespace MicType.Win.Core;

public static class L10n
{
    public static AppLanguage Language
    {
        get => SettingsStore.Instance.Current.AppLanguage;
        set
        {
            SettingsStore.Instance.Current.AppLanguage = value;
            SettingsStore.Instance.Save();
            LanguageChanged?.Invoke();
        }
    }

    public static event Action? LanguageChanged;

    public static string Tr(string zh, string en) => Language == AppLanguage.Zh ? zh : en;
}
