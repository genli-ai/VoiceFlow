using System.IO;

namespace MicType.Win.Services;

public sealed record SenseVoiceModelPaths(
    string ModelRoot,
    string ModelFile,
    string TokensFile,
    string[] TestWavFiles)
{
    public static readonly string[] RequiredFileNames = ["model.int8.onnx", "tokens.txt"];

    public static bool IsAvailable(string directory) => TryFind(directory, out _);

    public static SenseVoiceModelPaths Find(string directory)
    {
        if (TryFind(directory, out var paths))
        {
            return paths;
        }

        throw new FileNotFoundException(
            $"SenseVoice model files are incomplete under {directory}. Required: {string.Join(", ", RequiredFileNames)}.");
    }

    public static bool TryFind(string directory, out SenseVoiceModelPaths paths)
    {
        paths = new SenseVoiceModelPaths(directory, "", "", []);
        if (!Directory.Exists(directory)) return false;

        var modelFile = FindNonEmptyFile(directory, "model.int8.onnx");
        var tokensFile = FindNonEmptyFile(directory, "tokens.txt");
        if (modelFile is null || tokensFile is null) return false;

        var modelRoot = Path.GetDirectoryName(modelFile) ?? directory;
        var testWavsDir = Path.Combine(modelRoot, "test_wavs");
        var testWavs = Directory.Exists(testWavsDir)
            ? Directory.GetFiles(testWavsDir, "*.wav", SearchOption.TopDirectoryOnly)
            : [];

        paths = new SenseVoiceModelPaths(modelRoot, modelFile, tokensFile, testWavs);
        return true;
    }

    private static string? FindNonEmptyFile(string directory, string fileName)
    {
        return Directory
            .EnumerateFiles(directory, fileName, SearchOption.AllDirectories)
            .FirstOrDefault(path => new FileInfo(path).Length > 0);
    }
}
