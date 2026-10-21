import XCTest
@testable import CeyloroCore

final class EngineLocatorTests: XCTestCase {
    func testCustomFFmpegPathWinsWhenExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroEngine-\(UUID().uuidString)")
        let executable = root.appendingPathComponent("ffmpeg")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        XCTAssertEqual(FFmpegLocator().locate(customPath: executable.path), executable.standardizedFileURL)
    }

    func testNonExecutableCandidateIsIgnored() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroEngine-\(UUID().uuidString)")
        let directory = root.appendingPathComponent("bin", isDirectory: true)
        let executable = directory.appendingPathComponent("ffmpeg")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not executable".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable.path)

        XCTAssertNil(FFmpegLocator().locate(searchPaths: [directory], environmentPath: ""))
    }
}
