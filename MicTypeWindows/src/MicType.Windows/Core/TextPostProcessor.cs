using System.Text.RegularExpressions;

namespace MicType.Win.Core;

public static partial class TextPostProcessor
{
    public static string CleanTranscript(string text)
    {
        var value = BracketMarkerRegex().Replace(text, "");
        value = ParenthesesMarkerRegex().Replace(value, "");
        value = ShortRepeatRegex().Replace(value, "$1");
        value = LongRepeatRegex().Replace(value, "$1");
        return value.Trim();
    }

    public static string FixMixedPunctuation(string text)
    {
        var value = text;
        (string Full, string Half)[] pairs =
        [
            ("。", "."), ("，", ","), ("？", "?"), ("！", "!"), ("：", ":"), ("；", ";")
        ];

        foreach (var (full, half) in pairs)
        {
            value = Regex.Replace(value, "([\\p{L}0-9])" + Regex.Escape(full), "$1" + half);
        }

        return Regex.Replace(value, "([.,!?;:])([\\p{L}\\u4e00-\\u9fff])", "$1 $2");
    }

    public static string ApplyVocabReplacements(string text)
    {
        return ApplyVocabReplacements(text, SettingsStore.Instance.Current.VocabularyReplacements);
    }

    public static string ApplyVocabReplacements(
        string text,
        IReadOnlyList<(string Wrong, string Right)> replacements)
    {
        var value = text;
        foreach (var (wrong, right) in replacements)
        {
            value = value.Replace(wrong, right, StringComparison.Ordinal);
        }
        return value;
    }

    public static bool IsVocabEcho(string text, IReadOnlyList<string> terms)
    {
        if (string.IsNullOrWhiteSpace(text)) return false;
        if (text.StartsWith("常用词汇", StringComparison.Ordinal)) return true;
        if (terms.Count < 3) return false;

        var residue = text;
        var hits = 0;
        foreach (var term in terms)
        {
            if (!residue.Contains(term, StringComparison.Ordinal)) continue;
            hits++;
            residue = residue.Replace(term, "", StringComparison.Ordinal);
        }

        if (hits < 3) return false;
        residue = new string(residue.Where(c => !"、，,。.；; ：:".Contains(c)).ToArray());
        return residue.Length <= Math.Max(2, text.Length / 10);
    }

    [GeneratedRegex("\\[[^\\]]*\\]")]
    private static partial Regex BracketMarkerRegex();

    [GeneratedRegex("\\([^)]*\\)")]
    private static partial Regex ParenthesesMarkerRegex();

    [GeneratedRegex("(.{2,24}?)\\1{2,}", RegexOptions.Singleline)]
    private static partial Regex ShortRepeatRegex();

    [GeneratedRegex("(.{12,400}?)\\1+", RegexOptions.Singleline)]
    private static partial Regex LongRepeatRegex();
}
