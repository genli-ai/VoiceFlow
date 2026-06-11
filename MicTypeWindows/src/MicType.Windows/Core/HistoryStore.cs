using System.IO;
using System.Text.Json;

namespace MicType.Win.Core;

public sealed class HistoryStore
{
    public static HistoryStore Instance { get; } = new();
    private const int MaxCount = 20;
    private readonly List<HistoryItem> _items = [];

    private HistoryStore()
    {
        Load();
    }

    public IReadOnlyList<HistoryItem> Items => _items;

    public void Add(string raw, string polished)
    {
        _items.Insert(0, new HistoryItem(DateTimeOffset.Now, raw, polished));
        if (_items.Count > MaxCount)
        {
            _items.RemoveRange(MaxCount, _items.Count - MaxCount);
        }
        Save();
    }

    public void Clear()
    {
        _items.Clear();
        Save();
    }

    private void Save()
    {
        Directory.CreateDirectory(AppPaths.AppDataDir);
        File.WriteAllText(AppPaths.HistoryPath, JsonSerializer.Serialize(_items, new JsonSerializerOptions
        {
            WriteIndented = true
        }));
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(AppPaths.HistoryPath)) return;
            var items = JsonSerializer.Deserialize<List<HistoryItem>>(File.ReadAllText(AppPaths.HistoryPath));
            if (items is null) return;
            _items.Clear();
            _items.AddRange(items.Take(MaxCount));
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Failed to load history");
            _items.Clear();
        }
    }
}
