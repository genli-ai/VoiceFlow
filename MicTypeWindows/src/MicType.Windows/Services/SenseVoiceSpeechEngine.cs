using System.Diagnostics;
using MicType.Win.Core;
using SherpaOnnx;

namespace MicType.Win.Services;

public sealed class SenseVoiceSpeechEngine : ISpeechEngine
{
    private readonly SenseVoiceModelDownloader _modelDownloader;
    private readonly SemaphoreSlim _loadLock = new(1, 1);
    private readonly SemaphoreSlim _decodeLock = new(1, 1);
    private OfflineRecognizer? _recognizer;

    public SenseVoiceSpeechEngine(SenseVoiceModelDownloader? modelDownloader = null)
    {
        _modelDownloader = modelDownloader ?? SenseVoiceModelDownloader.Shared;
    }

    public string EngineName => "sherpa-onnx SenseVoice";
    public bool IsModelAvailable => _modelDownloader.IsModelAvailable;
    public bool IsModelLoaded => _recognizer is not null;

    public void Preload()
    {
        if (!IsModelAvailable || IsModelLoaded) return;
        Log.Info("Speech engine preload requested");
        _ = Task.Run(async () =>
        {
            try
            {
                await EnsureRecognizerAsync(CancellationToken.None);
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Speech engine preload failed");
            }
        });
    }

    public void UnloadModel()
    {
        Log.Info("Speech engine unload requested");
        _recognizer?.Dispose();
        _recognizer = null;
    }

    public async Task<string> TranscribeAsync(float[] samples, CancellationToken cancellationToken = default)
    {
        if (samples.Length == 0) return "";

        await _decodeLock.WaitAsync(cancellationToken);
        var stopwatch = Stopwatch.StartNew();
        try
        {
            var recognizer = await EnsureRecognizerAsync(cancellationToken);
            using var stream = recognizer.CreateStream();
            stream.AcceptWaveform(16000, samples);
            recognizer.Decode(stream);
            var text = stream.Result.Text.Trim();
            Log.Info($"Transcription completed elapsedMs={stopwatch.ElapsedMilliseconds} resultChars={text.Length}");
            return text;
        }
        catch (MTException ex)
        {
            Log.Error(ex, "Transcription failed with MTException");
            throw;
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Transcription failed");
            throw new MTException(L10n.Tr("识别失败：", "Transcription failed: ") + ex.Message);
        }
        finally
        {
            _decodeLock.Release();
        }
    }

    private async Task<OfflineRecognizer> EnsureRecognizerAsync(CancellationToken cancellationToken)
    {
        if (_recognizer is not null) return _recognizer;

        await _loadLock.WaitAsync(cancellationToken);
        var stopwatch = Stopwatch.StartNew();
        try
        {
            if (_recognizer is not null) return _recognizer;
            if (!IsModelAvailable)
            {
                Log.Warn("Speech model not available");
                throw new MTException(L10n.Tr(
                    "识别模型未下载，请在设置中下载。",
                    "Speech model not downloaded. Download it in Settings."));
            }

            var paths = _modelDownloader.FindModelFiles();
            var config = new OfflineRecognizerConfig();
            config.FeatConfig.SampleRate = 16000;
            config.FeatConfig.FeatureDim = 80;
            config.ModelConfig.Tokens = paths.TokensFile;
            config.ModelConfig.NumThreads = Math.Max(1, Math.Min(Environment.ProcessorCount / 2, 4));
            config.ModelConfig.Debug = 0;
            config.ModelConfig.Provider = "cpu";
            config.ModelConfig.SenseVoice.Model = paths.ModelFile;
            config.ModelConfig.SenseVoice.Language = "auto";
            config.ModelConfig.SenseVoice.UseInverseTextNormalization = 1;
            config.DecodingMethod = "greedy_search";
            config.MaxActivePaths = 4;

            _recognizer = new OfflineRecognizer(config);
            Log.Info(
                "Speech model loaded " +
                $"elapsedMs={stopwatch.ElapsedMilliseconds} modelRoot={paths.ModelRoot} threads={config.ModelConfig.NumThreads}");
            return _recognizer;
        }
        catch (MTException ex)
        {
            Log.Error(ex, "Failed to load speech model with MTException");
            throw;
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Failed to load speech model");
            throw new MTException(L10n.Tr("加载识别模型失败：", "Failed to load speech model: ") + ex.Message);
        }
        finally
        {
            _loadLock.Release();
        }
    }
}
