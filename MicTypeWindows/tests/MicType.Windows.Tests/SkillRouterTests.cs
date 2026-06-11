using MicType.Win.Services;

namespace MicType.Windows.Tests;

public sealed class SkillRouterTests
{
    [Theory]
    [InlineData("帮我回复一下客户")]
    [InlineData("回复一下，就说我同意")]
    public void ReplyTriggersMatch(string text)
    {
        Assert.True(SkillRouter.IsReplyTrigger(text));
    }

    [Fact]
    public void NonReplyTextDoesNotMatch()
    {
        Assert.False(SkillRouter.IsReplyTrigger("回头说这个事情"));
    }
}
