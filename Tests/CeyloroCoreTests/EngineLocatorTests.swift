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

    func testSearchPathFindsExecutableWithoutBundleLookup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroEngine-\(UUID().uuidString)")
        let resources = root.appendingPathComponent("Resources", isDirectory: true)
        let executable = resources.appendingPathComponent("ffmpeg")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        XCTAssertEqual(FFmpegLocator().locate(searchPaths: [resources], environmentPath: ""), executable.standardizedFileURL)
    }

    func testDocumentLocatorFindsLibreOfficeAndPandocInSearchPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroDocumentEngine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let libreOffice = root.appendingPathComponent("soffice")
        let pandoc = root.appendingPathComponent("pandoc")
        for executable in [libreOffice, pandoc] {
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }

        let locator = DocumentEngineLocator()
        XCTAssertEqual(locator.locateLibreOffice(searchPaths: [root], environmentPath: ""), libreOffice.standardizedFileURL)
        XCTAssertEqual(locator.locatePandoc(searchPaths: [root], environmentPath: ""), pandoc.standardizedFileURL)
    }
}
