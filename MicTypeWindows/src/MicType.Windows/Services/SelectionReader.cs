using System.Windows;
using System.Windows.Automation;

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
        catch
        {
            return null;
        }
    }

    public static async Task<string?> ReadSelectedTextWithClipboardFallbackAsync()
    {
        var direct = ReadSelectedText();
        if (!string.IsNullOrWhiteSpace(direct)) return direct;

        var oldText = TextInserter.GetClipboardText();
        TextInserter.SendCtrlC();
        await Task.Delay(350);

        string? copied = null;
        await Application.Current.Dispatcher.InvokeAsync(() =>
        {
            if (Clipboard.ContainsText())
            {
                var text = Clipboard.GetText();
                if (!string.IsNullOrWhiteSpace(text))
                {
                    copied = text;
                }
            }

            if (oldText is null)
            {
                Clipboard.Clear();
            }
            else
            {
                Clipboard.SetText(oldText);
            }
        });

        return copied;
    }
}
