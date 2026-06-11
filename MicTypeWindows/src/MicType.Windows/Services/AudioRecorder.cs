using MicType.Win.Core;
using NAudio.Wave;

namespace MicType.Win.Services;

public sealed class AudioRecorder : IDisposable
{
    private readonly object _lock = new();
    private WaveInEvent? _waveIn;
    private readonly List<float> _samples = [];

    public event Action<float>? LevelChanged;
    public bool IsRecording { get; private set; }

    public void Start()
    {
        if (IsRecording) return;

        lock (_lock)
        {
            _samples.Clear();
        }

        _waveIn = new WaveInEvent
        {
            WaveFormat = new WaveFormat(16000, 16, 1),
            BufferMilliseconds = 80
        };
        _waveIn.DataAvailable += OnDataAvailable;
        _waveIn.RecordingStopped += (_, _) => IsRecording = false;
        _waveIn.StartRecording();
        IsRecording = true;
    }

    public float[] Stop()
    {
        if (!IsRecording) return [];
        _waveIn?.StopRecording();
        _waveIn?.Dispose();
        _waveIn = null;
        IsRecording = false;

        lock (_lock)
        {
            var result = _samples.ToArray();
            _samples.Clear();
            return result;
        }
    }

    public void Dispose()
    {
        _waveIn?.Dispose();
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        var frameCount = e.BytesRecorded / 2;
        if (frameCount <= 0) return;

        var sum = 0.0;
        var chunk = new float[frameCount];
        for (var i = 0; i < frameCount; i++)
        {
            var sample = BitConverter.ToInt16(e.Buffer, i * 2) / 32768f;
            chunk[i] = sample;
            sum += sample * sample;
        }

        lock (_lock)
        {
            _samples.AddRange(chunk);
        }

        var rms = Math.Sqrt(sum / frameCount);
        LevelChanged?.Invoke((float)Math.Min(1.0, rms * 14.0));
    }
}
