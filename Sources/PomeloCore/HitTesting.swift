import Foundation

public struct RadialGeometry: Equatable, Sendable {
    public let innerRadius: Double
    public let outerRadius: Double
    public let outsideMultiplier: Double

    public init(innerRadius: Double = 54, outerRadius: Double = 154, outsideMultiplier: Double = 1.4) {
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.outsideMultiplier = outsideMultiplier
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
        if radius > geometry.outerRadius * geometry.outsideMultiplier { return .outside }

        let theta = (atan2(dx, dy) + (2 * Double.pi)).truncatingRemainder(dividingBy: 2 * Double.pi)
        let step = 2 * Double.pi / Double(sectorCount)
        let index = Int(floor((theta + Double.pi / Double(sectorCount)) / step)) % sectorCount
        return .sector(index)
    }
}
