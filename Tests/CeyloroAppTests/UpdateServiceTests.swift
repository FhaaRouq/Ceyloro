import CryptoKit
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

    // MARK: - B5 regression: validasi URL pembaruan

    func testInstallRejectsHTTPURL() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Ceyloro.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let release = makeRelease(
            archiveURL: URL(string: "http://evil.com/malware.zip")!,
            checksumURL: URL(string: "https://github.com/test/checksum.sha256")!
        )
        let service = CeyloroUpdateService()
        do {
            try await service.install(release: release, currentAppURL: appURL)
            XCTFail("Install with HTTP URL should throw.")
        } catch {
            // Expected: URL validation rejects non-HTTPS
        }
    }

    func testInstallRejectsNonGitHubHost() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Ceyloro.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let release = makeRelease(
            archiveURL: URL(string: "https://evil.com/malware.zip")!,
            checksumURL: URL(string: "https://github.com/test/checksum.sha256")!
        )
        let service = CeyloroUpdateService()
        do {
            try await service.install(release: release, currentAppURL: appURL)
            XCTFail("Install with non-GitHub host should throw.")
        } catch {
            // Expected: URL validation rejects non-GitHub host
        }
    }

    // MARK: - B5 regression: checksum salah

    func testInstallRejectsChecksumMismatch() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Ceyloro.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let archiveData = Data("fake archive content".utf8)
        let wrongChecksum = String(repeating: "0", count: 64)
        let checksumData = Data("\(wrongChecksum) archive.zip\n".utf8)

        let archiveURL = URL(string: "https://github.com/test/Ceyloro-macOS-universal.zip")!
        let checksumURL = URL(string: "https://github.com/test/Ceyloro-macOS-universal.zip.sha256")!

        MockURLProtocol.set(archiveURL, data: archiveData, status: 200)
        MockURLProtocol.set(checksumURL, data: checksumData, status: 200)
        defer { MockURLProtocol.reset() }

        let service = makeMockService()
        let release = makeRelease(archiveURL: archiveURL, checksumURL: checksumURL)

        do {
            try await service.install(release: release, currentAppURL: appURL)
            XCTFail("Install with wrong checksum should throw checksumMismatch.")
        } catch let error as CeyloroUpdateError {
            guard case .checksumMismatch = error else {
                return XCTFail("Expected checksumMismatch but got \(error)")
            }
        }
    }

    // MARK: - B5 regression: archive invalid (tidak berisi Ceyloro.app valid)

    func testInstallRejectsInvalidArchive() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Ceyloro.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        // Buat ZIP valid yang berisi file teks, bukan Ceyloro.app
        let archiveContents = root.appendingPathComponent("contents", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveContents, withIntermediateDirectories: true)
        try Data("not an app".utf8).write(to: archiveContents.appendingPathComponent("readme.txt"))
        let archivePath = root.appendingPathComponent("fake.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", archiveContents.path, archivePath.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw XCTSkip("ditto tidak dapat membuat ZIP fixture.") }

        let archiveData = try Data(contentsOf: archivePath)
        let digest = SHA256.hash(data: archiveData)
        let checksum = digest.map { String(format: "%02x", $0) }.joined()
        let checksumData = Data("\(checksum) archive.zip\n".utf8)

        let archiveURL = URL(string: "https://github.com/test/Ceyloro-macOS-universal.zip")!
        let checksumURL = URL(string: "https://github.com/test/Ceyloro-macOS-universal.zip.sha256")!

        MockURLProtocol.set(archiveURL, data: archiveData, status: 200)
        MockURLProtocol.set(checksumURL, data: checksumData, status: 200)
        defer { MockURLProtocol.reset() }

        let service = makeMockService()
        let release = makeRelease(archiveURL: archiveURL, checksumURL: checksumURL)

        do {
            try await service.install(release: release, currentAppURL: appURL)
            XCTFail("Install with invalid archive should throw invalidArchive.")
        } catch let error as CeyloroUpdateError {
            guard case .invalidArchive = error else {
                return XCTFail("Expected invalidArchive but got \(error)")
            }
        }
    }

    // MARK: - B5 regression: release tanpa asset macOS

    func testInstallRejectsMissingMacOSAsset() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Ceyloro.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let release = CeyloroUpdateRelease(
            tagName: "v0.1.1", name: "Test", body: nil,
            htmlURL: URL(string: "https://github.com/test")!,
            publishedAt: nil,
            assets: [
                CeyloroUpdateAsset(name: "Ceyloro-macOS-universal.zip.sha256",
                                   browserDownloadURL: URL(string: "https://github.com/test/checksum.sha256")!)
            ]
        )
        let service = CeyloroUpdateService()
        do {
            try await service.install(release: release, currentAppURL: appURL)
            XCTFail("Install without macOS asset should throw.")
        } catch let error as CeyloroUpdateError {
            guard case .releaseMissingMacOSAsset = error else {
                return XCTFail("Expected releaseMissingMacOSAsset but got \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroB5-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeRelease(archiveURL: URL, checksumURL: URL) -> CeyloroUpdateRelease {
        CeyloroUpdateRelease(
            tagName: "v0.1.1", name: "Test", body: nil,
            htmlURL: URL(string: "https://github.com/test")!,
            publishedAt: nil,
            assets: [
                CeyloroUpdateAsset(name: "Ceyloro-macOS-universal.zip", browserDownloadURL: archiveURL),
                CeyloroUpdateAsset(name: "Ceyloro-macOS-universal.zip.sha256", browserDownloadURL: checksumURL)
            ]
        )
    }

    private func makeMockService() -> CeyloroUpdateService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return CeyloroUpdateService(session: URLSession(configuration: config))
    }
}

// Mock URLProtocol untuk fault-injection testing (B5)
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var responses: [String: (data: Data, status: Int)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let key = request.url?.absoluteString,
              let response = Self.responses[key] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let httpResponse = HTTPURLResponse(
            url: request.url!, statusCode: response.status,
            httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func set(_ url: URL, data: Data, status: Int) {
        responses[url.absoluteString] = (data, status)
    }

    static func reset() { responses.removeAll() }
}
