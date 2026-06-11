using System.IO;

namespace MicType.Win.Core;

public static class AppPaths
{
    public static string AppDataDir
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "MicType");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string LocalDataDir
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "MicType");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string ModelsDir
    {
        get
        {
            var dir = Path.Combine(LocalDataDir, "models");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string SettingsPath => Path.Combine(AppDataDir, "settings.json");
    public static string HistoryPath => Path.Combine(AppDataDir, "history.json");

    public static string ModelDirectoryForRepo(string repo)
    {
        var dir = Path.Combine(ModelsDir, repo.Replace("/", "__"));
        Directory.CreateDirectory(dir);
        return dir;
    }
}
