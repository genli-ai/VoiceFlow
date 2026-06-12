using MicType.Win.Core;

namespace MicType.Windows.Tests;

public sealed class TimeoutRunnerTests
{
    [Fact]
    public async Task ReturnsFallbackWhenOperationIsSlow()
    {
        var started = DateTimeOffset.UtcNow;

        var result = await TimeoutRunner.RunAsync(
            Task.Run(async () =>
            {
                await Task.Delay(TimeSpan.FromSeconds(5));
                return "late";
            }),
            TimeSpan.FromMilliseconds(50),
            () => "timeout",
            "test timeout");

        Assert.Equal("timeout", result);
        Assert.True(DateTimeOffset.UtcNow - started < TimeSpan.FromSeconds(1));
    }
}
