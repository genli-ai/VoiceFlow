using MicType.Win.Core;

namespace MicType.Win.Services;

public sealed class ProcessingWatchdog
{
    private readonly TimeSpan _timeout;
    private readonly Func<Phase> _getPhase;
    private readonly Func<Task> _onTimeout;
    private CancellationTokenSource? _cts;

    public ProcessingWatchdog(TimeSpan timeout, Func<Phase> getPhase, Func<Task> onTimeout)
    {
        _timeout = timeout;
        _getPhase = getPhase;
        _onTimeout = onTimeout;
    }

    public void Arm()
    {
        Disarm();
        var cts = new CancellationTokenSource();
        _cts = cts;
        _ = WaitAndTriggerAsync(_getPhase, _onTimeout, _timeout, cts.Token);
    }

    public void Disarm()
    {
        _cts?.Cancel();
        _cts?.Dispose();
        _cts = null;
    }

    public static async Task<bool> WaitAndTriggerAsync(
        Func<Phase> getPhase,
        Func<Task> onTimeout,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(timeout, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            return false;
        }

        if (getPhase() != Phase.Processing) return false;

        Log.Warn("Processing watchdog timeout");
        await onTimeout();
        return true;
    }
}
