using MicType.Win.Core;

namespace MicType.Win.Services;

public interface ISpeechEngine
{
    string EngineName { get; }
    bool IsModelAvailable { get; }
    bool IsModelLoaded { get; }
    void Preload();
    void UnloadModel();
    Task<string> TranscribeAsync(float[] samples, CancellationToken cancellationToken = default);
}
