import XCTest
@testable import PomeloCore

final class PDFMergeTests: XCTestCase {
    func testNaturalSortPutsIMG2BeforeIMG10() {
        let urls = [
            URL(fileURLWithPath: "/tmp/IMG_10.jpg"),
            URL(fileURLWithPath: "/tmp/IMG_2.jpg"),
            URL(fileURLWithPath: "/tmp/IMG_1.jpg")
        ]
        let sorted = ImageSorting.sorted(urls, by: .nameAscending)
        XCTAssertEqual(sorted.map(\.lastPathComponent), ["IMG_1.jpg", "IMG_2.jpg", "IMG_10.jpg"])
    }

    func testDateSortUsesNameAsTieBreaker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PomeloSort-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var first = root.appendingPathComponent("IMG_10.jpg")
        var second = root.appendingPathComponent("IMG_2.jpg")
        FileManager.default.createFile(atPath: first.path, contents: Data())
        FileManager.default.createFile(atPath: second.path, contents: Data())
        var firstValues = URLResourceValues()
        firstValues.creationDate = Date(timeIntervalSince1970: 1_000)
        try first.setResourceValues(firstValues)
        var secondValues = URLResourceValues()
        secondValues.creationDate = Date(timeIntervalSince1970: 1_000)
        try second.setResourceValues(secondValues)
        let sorted = ImageSorting.sorted([first, second], by: .createdAscending)
        XCTAssertEqual(sorted.map(\.lastPathComponent), ["IMG_2.jpg", "IMG_10.jpg"])
    }

    func testMergeListModelMoveRemoveSortAndReverse() {
        var model = MergeListModel(items: [
            URL(fileURLWithPath: "/tmp/IMG_10.jpg"),
            URL(fileURLWithPath: "/tmp/IMG_2.jpg"),
            URL(fileURLWithPath: "/tmp/IMG_1.jpg")
        ])
        model.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(model.items.map(\.lastPathComponent), ["IMG_2.jpg", "IMG_1.jpg", "IMG_10.jpg"])
        model.sort(by: .nameAscending)
        XCTAssertEqual(model.items.map(\.lastPathComponent), ["IMG_1.jpg", "IMG_2.jpg", "IMG_10.jpg"])
        model.reverse()
        XCTAssertEqual(model.items.map(\.lastPathComponent), ["IMG_10.jpg", "IMG_2.jpg", "IMG_1.jpg"])
        model.remove(at: IndexSet(integer: 1))
        XCTAssertEqual(model.items.map(\.lastPathComponent), ["IMG_10.jpg", "IMG_1.jpg"])
    }

    func testPageLayoutPreservesAspectAndMargin() {
        let image = CGSize(width: 1200, height: 600)
        let page = PageLayout.pageSize(forImage: image, option: .a4)
        XCTAssertGreaterThan(page.width, page.height)
        let rect = PageLayout.imageRect(imageSize: image, pageSize: page, margin: .medium)
        XCTAssertLessThanOrEqual(rect.minX, page.width - 36)
        XCTAssertGreaterThanOrEqual(rect.minX, 36)
        XCTAssertEqual(rect.width / rect.height, image.width / image.height, accuracy: 0.001)
    }

    func testMatchImageLimitsLongSideTo842WithoutUpscaling() {
        let page = PageLayout.pageSize(forImage: CGSize(width: 1200, height: 600), option: .matchImage)
        XCTAssertEqual(page.width, 842, accuracy: 0.001)
        XCTAssertEqual(page.height, 421, accuracy: 0.001)
        let smallPage = PageLayout.pageSize(forImage: CGSize(width: 100, height: 50), option: .matchImage)
        XCTAssertEqual(smallPage.width, 100, accuracy: 0.001)
    }
}
