import XCTest
@testable import CeyloroCore

final class HitTestingTests: XCTestCase {
    func testTopIsFirstSector() {
        let result = RadialHitTesting.hit(point: CGPoint(x: 0, y: 100), center: .zero, sectorCount: 4)
        XCTAssertEqual(result, .sector(0))
    }

    func testHubAndOutside() {
        XCTAssertEqual(RadialHitTesting.hit(point: .zero, center: .zero, sectorCount: 6), .hub)
        XCTAssertEqual(RadialHitTesting.hit(point: CGPoint(x: 300, y: 0), center: .zero, sectorCount: 6), .outside)
    }

    func testOppositeSectorsDiffer() {
        let top = RadialHitTesting.hit(point: CGPoint(x: 0, y: 100), center: .zero, sectorCount: 8)
        let bottom = RadialHitTesting.hit(point: CGPoint(x: 0, y: -100), center: .zero, sectorCount: 8)
        XCTAssertNotEqual(top, bottom)
    }

    func testDefaultGeometryMatchesRenderedWheel() {
        let geometry = RadialGeometry()
        XCTAssertEqual(geometry.innerRadius, 54)
        XCTAssertEqual(geometry.outerRadius, 128)
        XCTAssertEqual(geometry.discRadius, 137)
        XCTAssertEqual(geometry.outsideMultiplier, 1.12)
        XCTAssertEqual(geometry.angularGapDegrees, 1.5)
    }

    func testBoundarySnapsToNearestSector() {
        // Point close to boundary between sector 0 (top) and sector 1 in a 4-sector wheel
        // Sector 0 step is 90 deg (from 45 deg to 135 deg). Angle ~44 deg should snap to sector 0 or 1, not .outside
        let rad = 44.0 * Double.pi / 180.0
        let p = CGPoint(x: 100 * sin(rad), y: 100 * cos(rad))
        let result = RadialHitTesting.hit(point: p, center: .zero, sectorCount: 4)
        XCTAssertNotEqual(result, .outside)
    }

    func testHubGapAndOutsideAreNotSectors() {
        let geometry = RadialGeometry()
        XCTAssertEqual(RadialHitTesting.hit(point: CGPoint(x: 0, y: 53), center: .zero, sectorCount: 4, geometry: geometry), .hub)
        XCTAssertEqual(RadialHitTesting.hit(point: CGPoint(x: 100, y: 100), center: .zero, sectorCount: 4, geometry: geometry), .outside)
        XCTAssertEqual(RadialHitTesting.hit(point: CGPoint(x: 138, y: 0), center: .zero, sectorCount: 4, geometry: geometry), .outside)
        XCTAssertEqual(RadialHitTesting.hit(point: CGPoint(x: 180, y: 0), center: .zero, sectorCount: 4, geometry: geometry), .outside)
    }
}
