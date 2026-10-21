import Foundation
import XCTest
@testable import Ceyloro

final class ArchiveConverterTests: XCTestCase {
    func testZipCanBeConvertedToTar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroArchive-\(UUID().uuidString)")
        let sourceFolder = root.appendingPathComponent("sample", isDirectory: true)
        let sourceZip = root.appendingPathComponent("source.zip")
        let temporaryDirectory = root.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("Ceyloro".utf8).write(to: sourceFolder.appendingPathComponent("hello.txt"))
        try run(executable: "/usr/bin/ditto", arguments: ["-c", "-k", "--keepParent", sourceFolder.path, sourceZip.path])

        let result = try ArchiveConverter().convert(input: sourceZip, target: .tar, temporaryDirectory: temporaryDirectory, progress: { _ in }, isCancelled: { false })
        let output = try XCTUnwrap(result.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(try tarContains(output, path: "hello.txt"))
    }

    func testGzipOutputUsesTarGzExtension() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroArchive-\(UUID().uuidString)")
        let sourceFolder = root.appendingPathComponent("sample", isDirectory: true)
        let sourceZip = root.appendingPathComponent("source.zip")
        let temporaryDirectory = root.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("Ceyloro".utf8).write(to: sourceFolder.appendingPathComponent("hello.txt"))
        try run(executable: "/usr/bin/ditto", arguments: ["-c", "-k", "--keepParent", sourceFolder.path, sourceZip.path])

        let result = try ArchiveConverter().convert(input: sourceZip, target: .gzip, temporaryDirectory: temporaryDirectory, progress: { _ in }, isCancelled: { false })
        let output = try XCTUnwrap(result.first)
        XCTAssertEqual(output.pathExtension, "gz")
        XCTAssertEqual(output.lastPathComponent, "output.tar.gz")
        XCTAssertTrue(try tarContains(output, path: "hello.txt"))
    }

    func testPlainGzipIsNotOfferedAsTarArchive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroArchive-\(UUID().uuidString)")
        let input = root.appendingPathComponent("notes.gz")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a tar archive".utf8).write(to: root.appendingPathComponent("notes.txt"))
        FileManager.default.createFile(atPath: input.path, contents: Data())
        try run(executable: "/usr/bin/gzip", arguments: ["-c", root.appendingPathComponent("notes.txt").path], output: input)

        let targets = ArchiveConverter().supportedTargets(for: [input], candidates: [.zip, .tar, .gzip])

        XCTAssertTrue(targets.isEmpty)
    }

    private func tarContains(_ archive: URL, path: String) throws -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-tf", archive.path]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
        let output = try pipe.fileHandleForReading.readToEnd().flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return output.split(whereSeparator: { $0 == "\n" }).contains { $0.hasSuffix(path) }
    }

    private func run(executable: String, arguments: [String], output: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let output {
            let handle = try FileHandle(forWritingTo: output)
            process.standardOutput = handle
        }
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "CeyloroTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Archive fixture gagal dibuat."])
        }
    }
}
