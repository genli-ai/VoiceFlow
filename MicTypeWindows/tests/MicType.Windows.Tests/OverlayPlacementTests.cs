using MicType.Win.Core;

namespace MicType.Windows.Tests;

public sealed class OverlayPlacementTests
{
    [Theory]
    [InlineData(1.0, 700, 956, 520, 96)]
    [InlineData(1.25, 635, 925, 650, 120)]
    [InlineData(1.5, 570, 894, 780, 144)]
    public void CalculatesBottomCenterForCommonScaleFactors(
        double scale,
        int expectedX,
        int expectedY,
        int expectedWidth,
        int expectedHeight)
    {
        var result = OverlayPlacement.Calculate(new PhysicalRect(0, 0, 1920, 1080), 520, 96, scale);

        Assert.Equal(expectedX, result.X);
        Assert.Equal(expectedY, result.Y);
        Assert.Equal(expectedWidth, result.WidthPx);
        Assert.Equal(expectedHeight, result.HeightPx);
    }

    [Fact]
    public void SupportsNegativeLeftMonitor()
    {
        var result = OverlayPlacement.Calculate(new PhysicalRect(-1920, 0, 1920, 1040), 520, 96, 1.25);

        Assert.Equal(-1285, result.X);
        Assert.Equal(885, result.Y);
    }

    [Fact]
    public void SupportsUltrawideWorkArea()
    {
        var result = OverlayPlacement.Calculate(new PhysicalRect(0, 0, 3440, 1392), 520, 96, 1.0);

        Assert.Equal(1460, result.X);
        Assert.Equal(1268, result.Y);
    }
}
