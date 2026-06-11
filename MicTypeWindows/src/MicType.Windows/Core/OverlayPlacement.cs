namespace MicType.Win.Core;

public readonly record struct PhysicalRect(int Left, int Top, int Width, int Height)
{
    public int Right => Left + Width;
    public int Bottom => Top + Height;
}

public readonly record struct OverlayPlacementResult(
    int X,
    int Y,
    int WidthPx,
    int HeightPx,
    double Scale,
    double DipX,
    double DipY);

public static class OverlayPlacement
{
    public static OverlayPlacementResult Calculate(
        PhysicalRect workArea,
        double windowWidthDip,
        double windowHeightDip,
        double scale,
        double bottomMarginDip = 28)
    {
        var safeScale = scale > 0 ? scale : 1;
        var widthPx = Math.Max(1, (int)Math.Round(windowWidthDip * safeScale));
        var heightPx = Math.Max(1, (int)Math.Round(windowHeightDip * safeScale));
        var bottomMarginPx = (int)Math.Round(bottomMarginDip * safeScale);
        var x = workArea.Left + (workArea.Width - widthPx) / 2;
        var y = workArea.Bottom - heightPx - bottomMarginPx;

        return new OverlayPlacementResult(
            x,
            y,
            widthPx,
            heightPx,
            safeScale,
            x / safeScale,
            y / safeScale);
    }
}
