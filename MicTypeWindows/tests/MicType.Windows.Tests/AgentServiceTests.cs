using MicType.Win.Core;
using MicType.Win.Services;

namespace MicType.Windows.Tests;

public sealed class AgentServiceTests
{
    [Fact]
    public void ParseSelectionResultParsesModify()
    {
        var parsed = AgentService.ParseSelectionResult("MODIFY\n改好的正文");

        Assert.Equal(SelectionAction.Modify, parsed.Action);
        Assert.Equal("改好的正文", parsed.Body);
    }

    [Fact]
    public void ParseSelectionResultParsesInlineReplyBody()
    {
        var parsed = AgentService.ParseSelectionResult("REPLY：可以，明天见");

        Assert.Equal(SelectionAction.Reply, parsed.Action);
        Assert.Equal("可以，明天见", parsed.Body);
    }

    [Fact]
    public void ParseSelectionResultKeepsBodyWhenNoIntent()
    {
        var parsed = AgentService.ParseSelectionResult("直接输出这段");

        Assert.Null(parsed.Action);
        Assert.Equal("直接输出这段", parsed.Body);
    }
}
