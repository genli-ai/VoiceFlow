using MicType.Win.Core;

namespace MicType.Windows.Tests;

public sealed class TextPostProcessorTests
{
    [Fact]
    public void VocabEchoDetectsPrefix()
    {
        Assert.True(TextPostProcessor.IsVocabEcho("常用词汇：Gen、MicType、Qwen", new[] { "Gen", "MicType", "Qwen" }));
    }

    [Fact]
    public void VocabEchoDetectsThreeHitsWithNoResidue()
    {
        Assert.True(TextPostProcessor.IsVocabEcho("Gen、MicType、Qwen。", new[] { "Gen", "MicType", "Qwen" }));
    }

    [Fact]
    public void VocabEchoDoesNotKillNormalSentence()
    {
        Assert.False(TextPostProcessor.IsVocabEcho("今天用 MicType 给 Gen 发消息。", new[] { "Gen", "MicType", "Qwen" }));
    }

    [Fact]
    public void FixMixedPunctuationConvertsFullWidthAfterEnglish()
    {
        Assert.Equal("Open API, 然后测试。", TextPostProcessor.FixMixedPunctuation("Open API，然后测试。"));
    }

    [Fact]
    public void FixMixedPunctuationKeepsChinesePunctuationAfterChinese()
    {
        Assert.Equal("你好，世界。", TextPostProcessor.FixMixedPunctuation("你好，世界。"));
    }
}
