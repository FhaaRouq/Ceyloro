import Foundation

public struct RadialGeometry: Equatable, Sendable {
    public let innerRadius: Double
    public let outerRadius: Double
    public let discRadius: Double
    public let outsideMultiplier: Double
    public let angularGapDegrees: Double

    public init(innerRadius: Double = 54, outerRadius: Double = 128, outsideMultiplier: Double = 1.12, angularGapDegrees: Double = 5, discRadius: Double = 137) {
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.discRadius = discRadius
        self.outsideMultiplier = outsideMultiplier
        self.angularGapDegrees = angularGapDegrees
    }
}

public enum RadialHit: Equatable, Sendable {
    case hub
    case sector(Int)
    case outside
}

public enum RadialHitTesting {
    public static func hit(point: CGPoint, center: CGPoint, sectorCount: Int, geometry: RadialGeometry = RadialGeometry()) -> RadialHit {
        guard sectorCount > 0 else { return .outside }
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        let radius = hypot(dx, dy)
        if radius < geometry.innerRadius { return .hub }
        let outsideRadius = min(geometry.discRadius, geometry.outerRadius * geometry.outsideMultiplier)
        if radius > outsideRadius { return .outside }

        let theta = (atan2(dx, dy) + (2 * Double.pi)).truncatingRemainder(dividingBy: 2 * Double.pi)
        let step = 2 * Double.pi / Double(sectorCount)
        let index = Int(floor((theta + Double.pi / Double(sectorCount)) / step)) % sectorCount
        let midpoint = Double(index) * step
        let angularDistance = abs(atan2(sin(theta - midpoint), cos(theta - midpoint)))
        let allowedHalfWidth = step / 2 - geometry.angularGapDegrees * Double.pi / 180
        if angularDistance > allowedHalfWidth { return .outside }
        return .sector(index)
    }
}
