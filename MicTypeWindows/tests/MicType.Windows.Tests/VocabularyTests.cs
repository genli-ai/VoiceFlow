using MicType.Win.Core;

namespace MicType.Windows.Tests;

public sealed class VocabularyTests
{
    [Fact]
    public void ParsesPlainTermsAndReplacements()
    {
        var parsed = AppSettings.ParseVocabulary("Gen, 杰文=捷文，Qwen");

        Assert.Equal(new[] { "Gen", "捷文", "Qwen" }, parsed.Terms);
        Assert.Equal(new (string Wrong, string Right)[] { ("杰文", "捷文") }, parsed.Replacements);
    }

    [Fact]
    public void ParsesFullWidthEqualsAndIgnoresInvalidEntries()
    {
        var parsed = AppSettings.ParseVocabulary("杰文＝捷文, =空, 缺=, 普通词");

        Assert.Equal(new[] { "捷文", "普通词" }, parsed.Terms);
        Assert.Equal(new (string Wrong, string Right)[] { ("杰文", "捷文") }, parsed.Replacements);
    }

    [Fact]
    public void ApplyVocabReplacementsReplacesAllOccurrences()
    {
        var text = TextPostProcessor.ApplyVocabReplacements(
            "杰文说杰文今天到。",
            new (string Wrong, string Right)[] { ("杰文", "捷文") });

        Assert.Equal("捷文说捷文今天到。", text);
    }

    [Fact]
    public void ApplyVocabReplacementsWithEmptyListReturnsOriginal()
    {
        Assert.Equal("hello", TextPostProcessor.ApplyVocabReplacements("hello", Array.Empty<(string Wrong, string Right)>()));
    }
}
