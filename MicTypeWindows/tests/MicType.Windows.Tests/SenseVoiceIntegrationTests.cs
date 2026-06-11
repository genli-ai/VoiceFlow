using MicType.Win.Services;

namespace MicType.Windows.Tests;

public sealed class SenseVoiceIntegrationTests
{
    [Fact]
    public async Task TranscribesOfficialChineseSample()
    {
        if (Environment.GetEnvironmentVariable("MICTYPE_RUN_SENSEVOICE_INTEGRATION") != "1")
        {
            return;
        }

        var modelDir = Environment.GetEnvironmentVariable("MICTYPE_SENSEVOICE_MODEL_DIR");
        Assert.False(string.IsNullOrWhiteSpace(modelDir));

        var downloader = new SenseVoiceModelDownloader(modelDir);
        if (!downloader.IsModelAvailable)
        {
            await downloader.DownloadAsync();
        }

        var paths = downloader.FindModelFiles();
        var zhWav = paths.TestWavFiles.FirstOrDefault(path =>
            string.Equals(Path.GetFileName(path), "zh.wav", StringComparison.OrdinalIgnoreCase));
        Assert.False(string.IsNullOrWhiteSpace(zhWav));

        var (sampleRate, samples) = ReadMono16BitPcm(zhWav!);
        Assert.Equal(16000, sampleRate);
        Assert.NotEmpty(samples);

        var engine = new SenseVoiceSpeechEngine(downloader);
        var text = await engine.TranscribeAsync(samples);
        engine.UnloadModel();

        Assert.Contains("开放时间", text);
        Assert.Contains("下午5点", text);
    }

    private static (int SampleRate, float[] Samples) ReadMono16BitPcm(string path)
    {
        using var stream = File.OpenRead(path);
        using var reader = new BinaryReader(stream);

        var riff = new string(reader.ReadChars(4));
        _ = reader.ReadInt32();
        var wave = new string(reader.ReadChars(4));
        Assert.Equal("RIFF", riff);
        Assert.Equal("WAVE", wave);

        short channels = 0;
        int sampleRate = 0;
        short bitsPerSample = 0;
        byte[]? data = null;

        while (stream.Position < stream.Length)
        {
            var chunkId = new string(reader.ReadChars(4));
            var chunkSize = reader.ReadInt32();
            if (chunkId == "fmt ")
            {
                var audioFormat = reader.ReadInt16();
                channels = reader.ReadInt16();
                sampleRate = reader.ReadInt32();
                _ = reader.ReadInt32();
                _ = reader.ReadInt16();
                bitsPerSample = reader.ReadInt16();
                if (chunkSize > 16)
                {
                    reader.ReadBytes(chunkSize - 16);
                }

                Assert.Equal(1, audioFormat);
            }
            else if (chunkId == "data")
            {
                data = reader.ReadBytes(chunkSize);
                break;
            }
            else
            {
                reader.ReadBytes(chunkSize);
            }

            if (chunkSize % 2 == 1 && stream.Position < stream.Length)
            {
                reader.ReadByte();
            }
        }

        Assert.Equal(1, channels);
        Assert.Equal(16, bitsPerSample);
        Assert.NotNull(data);

        var samples = new float[data!.Length / 2];
        for (var i = 0; i < samples.Length; i++)
        {
            samples[i] = BitConverter.ToInt16(data, i * 2) / 32768f;
        }

        return (sampleRate, samples);
    }
}
