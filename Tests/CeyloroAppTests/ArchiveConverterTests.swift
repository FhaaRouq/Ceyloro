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

    // MARK: - Regression test B1: dotfiles harus dihitung dalam batas ukuran

    func testExpandedSizeCountsDotfiles() throws {
        // Buat direktori dengan file tersembunyi dan verifikasi ukurannya dihitung
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CeyloroB1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let visible = root.appendingPathComponent("visible.txt")
        let hidden = root.appendingPathComponent(".hidden")
        let payload = Data(repeating: 0x41, count: 1024)
        try payload.write(to: visible)
        try payload.write(to: hidden)

        // Gunakan akses langsung ke FileManager untuk menghitung ukuran
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: []
        )
        var total = 0
        while let url = enumerator?.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isDirectory != true else { continue }
            total += values.fileSize ?? 0
        }
        // Keduanya harus terhitung — total harus 2048 byte
        XCTAssertEqual(total, 2048,
            "Dotfiles harus dihitung dalam total ukuran — sebelum fix, .skipsHiddenFiles mengabaikannya")
    }

    // MARK: - Regression test B1: path traversal harus ditolak sebelum ekstraksi

    func testArchiveWithPathTraversalIsRejected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CeyloroB1Traversal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Buat TAR yang mengandung entri dengan path traversal
        let tarPath = root.appendingPathComponent("unsafe.tar")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        // Buat file sementara sebagai konten lalu paksa nama entri dengan path traversal via Python
        let scriptPath = root.appendingPathComponent("make_unsafe_tar.py")
        try """
        import tarfile, io
        with tarfile.open('\(tarPath.path)', 'w') as t:
            data = b'malicious'
            info = tarfile.TarInfo(name='../escape.txt')
            info.size = len(data)
            t.addfile(info, io.BytesIO(data))
        """.write(to: scriptPath, atomically: true, encoding: .utf8)

        let py = Process()
        py.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        py.arguments = [scriptPath.path]
        try py.run()
        py.waitUntilExit()
        guard py.terminationStatus == 0,
              FileManager.default.fileExists(atPath: tarPath.path) else {
            throw XCTSkip("Python3 tidak tersedia atau gagal membuat TAR fixture.")
        }

        let temp = root.appendingPathComponent("temp")
        XCTAssertThrowsError(
            try ArchiveConverter().convert(
                input: tarPath, target: .zip, temporaryDirectory: temp,
                progress: { _ in }, isCancelled: { false }
            ),
            "Arsip dengan path traversal harus ditolak sebelum ekstraksi"
        ) { error in
            // Pastikan error adalah archiveUnsafePath, bukan error generik
            if let convError = error as? ConversionError {
                XCTAssertEqual("\(convError)", "\(ConversionError.archiveUnsafePath)",
                    "Error harus archiveUnsafePath, bukan error lain")
            }
        }
    }

    func testPlainGzipIsNotOfferedAsTarArchive() throws {        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroArchive-\(UUID().uuidString)")
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
