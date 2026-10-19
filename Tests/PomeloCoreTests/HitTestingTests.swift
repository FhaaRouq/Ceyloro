import XCTest
@testable import PomeloCore

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
}
