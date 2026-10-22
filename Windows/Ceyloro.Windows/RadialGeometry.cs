using System.Drawing;

namespace Ceyloro.Windows;

public static class RadialGeometry
{
    public const float InnerRadius = 66f;
    public const float OuterRadius = 154f;

    public static int HitTest(Point center, Point point, int sectorCount) =>
        TargetIndexAt(point.X - center.X, point.Y - center.Y, sectorCount);

    public static int TargetIndexAt(int dx, int dy, int targetCount, double innerRadius = 66, double outerRadius = 154, double gapDegrees = 7)
    {
        if (targetCount <= 0)
            return -1;

        var radius = Math.Sqrt((double)dx * dx + (double)dy * dy);
        if (radius < innerRadius || radius > outerRadius)
            return -1;

        var angle = Math.Atan2(dy, dx) * 180 / Math.PI + 90;
        return TargetIndexAtAngle(angle, targetCount, gapDegrees);
    }

    internal static int TargetIndexAtAngle(double angle, int targetCount, double gapDegrees = 7)
    {
        if (targetCount <= 0)
            return -1;

        var step = 360d / targetCount;
        var normalizedAngle = ((angle % 360) + 360) % 360;
        var index = (int)Math.Floor((normalizedAngle + step / 2) / step) % targetCount;
        var centerAngle = index * step;
        var delta = ((normalizedAngle - centerAngle + 540) % 360) - 180;
        var halfPetal = Math.Max(0, step - gapDegrees) / 2;
        return Math.Abs(delta) <= halfPetal ? index : -1;
    }
}
