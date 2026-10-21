using System.Drawing;

namespace Ceyloro.Windows;

public static class RadialGeometry
{
    public const float InnerRadius = 66f;
    public const float OuterRadius = 154f;

    /// <summary>
    /// Computes the active sector index (0 to sectorCount - 1) for a given point relative to center,
    /// or returns -1 if the point lies outside the ring bounds or sectorCount is 0.
    /// Sector 0 is centered at 12 o'clock (-90 degrees in Cartesian, 0 degrees in clock coordinates)
    /// and sectors proceed clockwise.
    /// </summary>
    public static int HitTest(Point center, Point point, int sectorCount)
    {
        if (sectorCount <= 0) return -1;
        var dx = point.X - center.X;
        var dy = point.Y - center.Y;
        var radius = Math.Sqrt(dx * dx + dy * dy);
        if (radius < InnerRadius || radius > OuterRadius)
            return -1;

        var step = 360d / sectorCount;
        var degrees = Math.Atan2(dy, dx) * 180 / Math.PI + 90;
        if (degrees < 0) degrees += 360;
        var normalized = (degrees + step / 2) % 360;
        return (int)(normalized / step) % sectorCount;
    }
}
