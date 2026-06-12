namespace MicType.Win.Core;

public static class TimeoutRunner
{
    public static async Task<T> RunAsync<T>(
        Task<T> operation,
        TimeSpan timeout,
        Func<T> onTimeout,
        string logMessage,
        CancellationToken cancellationToken = default)
    {
        var delay = Task.Delay(timeout, cancellationToken);
        var completed = await Task.WhenAny(operation, delay);
        if (completed == operation)
        {
            return await operation;
        }

        Log.Warn(logMessage);
        _ = operation.ContinueWith(
            task => Log.Error(task.Exception!, logMessage + " background operation later failed"),
            TaskContinuationOptions.OnlyOnFaulted);
        return onTimeout();
    }
}
