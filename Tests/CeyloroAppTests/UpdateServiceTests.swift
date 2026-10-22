import Foundation
import XCTest
@testable import Ceyloro

final class UpdateServiceTests: XCTestCase {
    func testVersionComparisonNormalizesPrefixAndMissingComponents() {
        XCTAssertGreaterThan(CeyloroVersion("v0.1.1"), CeyloroVersion("0.1.0"))
        XCTAssertEqual(CeyloroVersion("v1.2"), CeyloroVersion("1.2.0"))
        XCTAssertLessThan(CeyloroVersion("0.9.9"), CeyloroVersion("1.0.0"))
    }

    func testReleaseDecodingFindsMacOSArchiveAndChecksum() throws {
        let json = #"""
        {
          "tag_name": "v0.1.1",
          "name": "Ceyloro 0.1.1",
          "body": "Perbaikan dan pembaruan.",
          "html_url": "https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/releases/tag/v0.1.1",
          "published_at": "2026-10-22T00:00:00Z",
          "assets": [
            {
              "name": "Ceyloro-macOS-universal.zip",
              "browser_download_url": "https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/releases/download/v0.1.1/Ceyloro-macOS-universal.zip"
            },
            {
              "name": "Ceyloro-macOS-universal.zip.sha256",
              "browser_download_url": "https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/releases/download/v0.1.1/Ceyloro-macOS-universal.zip.sha256"
            }
          ]
        }
        """#.data(using: .utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try XCTUnwrap(json)
        let release = try decoder.decode(CeyloroUpdateRelease.self, from: data)

        XCTAssertEqual(release.version, CeyloroVersion("0.1.1"))
        XCTAssertEqual(release.macOSAsset?.name, "Ceyloro-macOS-universal.zip")
        XCTAssertEqual(release.checksumAsset?.name, "Ceyloro-macOS-universal.zip.sha256")
        XCTAssertEqual(release.body, "Perbaikan dan pembaruan.")
    }
}
