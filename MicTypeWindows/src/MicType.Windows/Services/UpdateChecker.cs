using System.IO;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using MicType.Win.Core;

namespace MicType.Win.Services;

/// 轻量更新检查（对齐 Mac 版）：查 GitHub Releases latest → 比版本 → 下载 win-x64 zip
/// 到「下载」文件夹并在资源管理器中选中。不做自动替换——用户解压换一次 exe 即完成升级。
public static class UpdateChecker
{
    public const string ReleasesPage = "https://github.com/genli-ai/MicType/releases/latest";
    private const string LatestApi = "https://api.github.com/repos/genli-ai/MicType/releases/latest";

    private static readonly HttpClient Client = CreateClient();

    public sealed record CheckResult(CheckOutcome Outcome, string Version, string? FilePath = null, string? Error = null);

    public enum CheckOutcome
    {
        UpToDate,
        Downloaded,
        NoWindowsAsset,
        Failed
    }

    public static string CurrentVersion
    {
        get
        {
            var v = typeof(UpdateChecker).Assembly.GetName().Version;
            return v is null ? "0" : $"{v.Major}.{v.Minor}.{v.Build}";
        }
    }

    public static async Task<CheckResult> CheckAndDownloadAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var release = await Client.GetFromJsonAsync<ReleaseInfo>(LatestApi, cancellationToken);
            if (release?.TagName is null)
            {
                return new CheckResult(CheckOutcome.Failed, CurrentVersion, Error: "Unexpected response from GitHub");
            }

            var latest = release.TagName.TrimStart('v', 'V');
            Log.Info($"Update check latest={latest} current={CurrentVersion}");
            if (!IsNewer(latest, CurrentVersion))
            {
                return new CheckResult(CheckOutcome.UpToDate, CurrentVersion);
            }

            var asset = release.Assets?.FirstOrDefault(a =>
                a.Name is not null && a.Name.EndsWith("-win-x64.zip", StringComparison.OrdinalIgnoreCase));
            if (asset?.DownloadUrl is null)
            {
                // 最新 release 还没附 Windows 包（例如 Mac 专属小版本）——不算可更新
                Log.Info($"Update check: release {latest} has no win-x64 asset");
                return new CheckResult(CheckOutcome.NoWindowsAsset, latest);
            }

            var downloads = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            var dir = Path.Combine(downloads, "Downloads");
            Directory.CreateDirectory(dir);
            var dest = Path.Combine(dir, asset.Name!);

            await using (var remote = await Client.GetStreamAsync(asset.DownloadUrl, cancellationToken))
            await using (var file = File.Create(dest))
            {
                await remote.CopyToAsync(file, cancellationToken);
            }
            Log.Info($"Update downloaded {asset.Name} -> Downloads");

            System.Diagnostics.Process.Start("explorer.exe", $"/select,\"{dest}\"");
            return new CheckResult(CheckOutcome.Downloaded, latest, dest);
        }
        catch (Exception ex)
        {
            Log.Warn("Update check failed: " + ex.Message);
            return new CheckResult(CheckOutcome.Failed, CurrentVersion, Error: ex.Message);
        }
    }

    /// 数字分段比较："3.2.13" vs "3.2.9" → true
    public static bool IsNewer(string a, string b)
    {
        var pa = a.Split('.').Select(x => int.TryParse(x, out var n) ? n : 0).ToArray();
        var pb = b.Split('.').Select(x => int.TryParse(x, out var n) ? n : 0).ToArray();
        for (var i = 0; i < Math.Max(pa.Length, pb.Length); i++)
        {
            var x = i < pa.Length ? pa[i] : 0;
            var y = i < pb.Length ? pb[i] : 0;
            if (x != y) return x > y;
        }
        return false;
    }

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("MicType-Windows");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }

    private sealed record ReleaseInfo(
        [property: JsonPropertyName("tag_name")] string? TagName,
        [property: JsonPropertyName("assets")] List<AssetInfo>? Assets);

    private sealed record AssetInfo(
        [property: JsonPropertyName("name")] string? Name,
        [property: JsonPropertyName("browser_download_url")] string? DownloadUrl);
}
