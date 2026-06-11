using MicType.Win.Services;

namespace MicType.Windows.Tests;

public sealed class SenseVoiceModelPathsTests
{
    [Fact]
    public void FindsRequiredFilesInsideExtractedModelFolder()
    {
        var root = Path.Combine(Path.GetTempPath(), "mictype-sensevoice-test-" + Guid.NewGuid().ToString("N"));
        try
        {
            var modelRoot = Path.Combine(root, SenseVoiceModelDownloader.ModelId);
            Directory.CreateDirectory(modelRoot);
            File.WriteAllText(Path.Combine(modelRoot, "model.int8.onnx"), "model");
            File.WriteAllText(Path.Combine(modelRoot, "tokens.txt"), "tokens");

            Assert.True(SenseVoiceModelPaths.IsAvailable(root));
            var paths = SenseVoiceModelPaths.Find(root);
            Assert.Equal(modelRoot, paths.ModelRoot);
            Assert.EndsWith("model.int8.onnx", paths.ModelFile);
            Assert.EndsWith("tokens.txt", paths.TokensFile);
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void RejectsZeroByteRequiredFile()
    {
        var root = Path.Combine(Path.GetTempPath(), "mictype-sensevoice-test-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(root);
            File.WriteAllText(Path.Combine(root, "model.int8.onnx"), "");
            File.WriteAllText(Path.Combine(root, "tokens.txt"), "tokens");

            Assert.False(SenseVoiceModelPaths.IsAvailable(root));
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public void ExposesPrimaryAndMirrorUrls()
    {
        var urls = SenseVoiceModelDownloader.BuildArchiveUris();

        Assert.Contains(SenseVoiceModelDownloader.ArchiveFileName, urls[0].ToString());
        Assert.True(urls.Length >= 2);
    }
}
