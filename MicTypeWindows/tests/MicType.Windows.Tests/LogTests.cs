using MicType.Win.Core;

namespace MicType.Windows.Tests;

public sealed class LogTests
{
    [Fact]
    public void WritesCurrentDayLog()
    {
        var root = TempRoot();
        try
        {
            Log.Initialize(root, () => new DateTimeOffset(2026, 6, 11, 10, 0, 0, TimeSpan.Zero));
            Log.Info("hello");

            var path = Path.Combine(root, "mictype-20260611.log");
            Assert.True(File.Exists(path));
            Assert.Contains("hello", File.ReadAllText(path));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void RollsByDay()
    {
        var root = TempRoot();
        try
        {
            Log.Initialize(root, () => new DateTimeOffset(2026, 6, 11, 23, 59, 0, TimeSpan.Zero));
            Log.Info("day one");
            Log.Initialize(root, () => new DateTimeOffset(2026, 6, 12, 0, 1, 0, TimeSpan.Zero));
            Log.Info("day two");

            Assert.Contains("day one", File.ReadAllText(Path.Combine(root, "mictype-20260611.log")));
            Assert.Contains("day two", File.ReadAllText(Path.Combine(root, "mictype-20260612.log")));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void CleansLogsOlderThanSevenDays()
    {
        var root = TempRoot();
        try
        {
            File.WriteAllText(Path.Combine(root, "mictype-20260603.log"), "old");
            File.WriteAllText(Path.Combine(root, "mictype-20260604.log"), "keep");

            Log.Initialize(root, () => new DateTimeOffset(2026, 6, 11, 10, 0, 0, TimeSpan.Zero));

            Assert.False(File.Exists(Path.Combine(root, "mictype-20260603.log")));
            Assert.True(File.Exists(Path.Combine(root, "mictype-20260604.log")));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static string TempRoot()
    {
        var root = Path.Combine(Path.GetTempPath(), "mictype-log-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        return root;
    }
}
