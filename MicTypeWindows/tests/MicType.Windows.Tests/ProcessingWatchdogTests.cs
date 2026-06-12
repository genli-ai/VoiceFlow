using MicType.Win.Core;
using MicType.Win.Services;

namespace MicType.Windows.Tests;

public sealed class ProcessingWatchdogTests
{
    [Fact]
    public async Task TriggersWhenProcessingDoesNotExit()
    {
        var triggered = false;

        var result = await ProcessingWatchdog.WaitAndTriggerAsync(
            () => Phase.Processing,
            () =>
            {
                triggered = true;
                return Task.CompletedTask;
            },
            TimeSpan.FromMilliseconds(20),
            CancellationToken.None);

        Assert.True(result);
        Assert.True(triggered);
    }

    [Fact]
    public async Task DoesNotTriggerWhenPhaseHasRecovered()
    {
        var triggered = false;

        var result = await ProcessingWatchdog.WaitAndTriggerAsync(
            () => Phase.Idle,
            () =>
            {
                triggered = true;
                return Task.CompletedTask;
            },
            TimeSpan.FromMilliseconds(20),
            CancellationToken.None);

        Assert.False(result);
        Assert.False(triggered);
    }
}
