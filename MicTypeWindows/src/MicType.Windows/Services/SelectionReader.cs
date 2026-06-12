using System.Windows.Automation;
using MicType.Win.Core;

namespace MicType.Win.Services;

public static class SelectionReader
{
    public static string? ReadSelectedText()
    {
        try
        {
            var focused = AutomationElement.FocusedElement;
            if (focused is null) return null;
            if (!focused.TryGetCurrentPattern(TextPattern.Pattern, out var patternObj)) return null;
            var pattern = (TextPattern)patternObj;
            var ranges = pattern.GetSelection();
            var text = string.Join("", ranges.Select(r => r.GetText(-1)));
            return string.IsNullOrWhiteSpace(text) ? null : text;
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Failed to read selected text through UI Automation");
            return null;
        }
    }

    public static async Task<string?> ReadSelectedTextWithClipboardFallbackAsync()
    {
        var direct = ReadSelectedText();
        if (!string.IsNullOrWhiteSpace(direct)) return direct;

        var oldText = await TextInserter.GetClipboardTextAsync();
        TextInserter.SendCtrlC();
        await Task.Delay(350);

        var copied = await TextInserter.GetClipboardTextAsync();
        if (oldText is null)
        {
            await TextInserter.ClearClipboardAsync();
        }
        else
        {
            await TextInserter.SetClipboardTextAsync(oldText);
        }

        return string.IsNullOrWhiteSpace(copied) ? null : copied;
    }
}
