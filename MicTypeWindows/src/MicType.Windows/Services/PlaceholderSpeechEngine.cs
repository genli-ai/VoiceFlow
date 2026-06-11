using MicType.Win.Core;

namespace MicType.Win.Services;

public sealed class PlaceholderSpeechEngine : ISpeechEngine
{
    public string EngineName => "Windows ASR placeholder";
    public bool IsModelAvailable => true;
    public bool IsModelLoaded => false;

    public void Preload()
    {
    }

    public void UnloadModel()
    {
    }

    public Task<string> TranscribeAsync(float[] samples, CancellationToken cancellationToken = default)
    {
        throw new MTException(L10n.Tr(
            "Windows 本地 ASR 引擎尚未接入。请先完成 M0：在 Windows 11 真机上验证 sherpa-onnx / whisper.cpp 后再启用。",
            "Windows local ASR is not wired yet. Complete M0 on a real Windows 11 machine before enabling sherpa-onnx / whisper.cpp."));
    }
}
