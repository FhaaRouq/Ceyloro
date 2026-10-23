import XCTest
@testable import CeyloroCore

final class JobRunnerTests: XCTestCase {
    func testFailedCrossVolumeMoveDoesNotDeleteExistingDestination() throws {
        let runner = JobRunner()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroMove-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source.bin")
        let destination = root.appendingPathComponent("destination.bin")
        try Data([0x01, 0x02]).write(to: source)
        try Data([0xAA, 0xBB]).write(to: destination)

        XCTAssertThrowsError(try runner.moveSafely(from: source, to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), Data([0xAA, 0xBB]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCancelledQueuedJobPublishesCancelledSnapshot() {
        let runner = JobRunner(maxConcurrentJobs: 1)
        let firstStarted = expectation(description: "first job started")
        let secondCancelled = expectation(description: "second job cancelled")
        let releaseFirst = DispatchSemaphore(value: 0)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroRunner-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstInput = directory.appendingPathComponent("first.input")
        let secondInput = directory.appendingPathComponent("second.input")
        FileManager.default.createFile(atPath: firstInput.path, contents: Data())
        FileManager.default.createFile(atPath: secondInput.path, contents: Data())
        var firstID: UUID?

        firstID = runner.submit(inputs: [firstInput], target: .png, processor: { _, _, _, _, _ in
            firstStarted.fulfill()
            releaseFirst.wait()
            return []
        }) { snapshot in
            guard snapshot.id == firstID else { return }
        }

        wait(for: [firstStarted], timeout: 2)

        let secondID = runner.submit(inputs: [secondInput], target: .png, processor: { _, _, _, _, _ in
            XCTFail("Queued job should be cancelled before its processor runs")
            return []
        }) { snapshot in
            if snapshot.state == .cancelled {
                secondCancelled.fulfill()
            }
        }
        runner.cancel(id: secondID)
        wait(for: [secondCancelled], timeout: 2)

        releaseFirst.signal()
    }

    func testTempDirectoryIsRemovedAfterCompletion() {
        let runner = JobRunner(maxConcurrentJobs: 1)
        let completed = expectation(description: "job completed")
        let input = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroRunner-\(UUID().uuidString).input")
        FileManager.default.createFile(atPath: input.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: input) }
        var jobID: UUID?

        jobID = runner.submit(inputs: [input], target: .png, processor: { _, _, temporaryDirectory, _, _ in
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let output = temporaryDirectory.appendingPathComponent("output.png")
            try Data([0x01]).write(to: output)
            return [output]
        }) { snapshot in
            if snapshot.id == jobID, snapshot.state == .completed {
                completed.fulfill()
            }
        }

        wait(for: [completed], timeout: 2)
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Ceyloro-\(jobID!.uuidString)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.path))
    }

    func testOneFailedFileDoesNotAbortTheBatch() {
        let runner = JobRunner(maxConcurrentJobs: 1)
        let completed = expectation(description: "batch completed")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroRunner-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("failing.input")
        let second = directory.appendingPathComponent("success.input")
        FileManager.default.createFile(atPath: first.path, contents: Data())
        FileManager.default.createFile(atPath: second.path, contents: Data())

        let jobID = runner.submit(inputs: [first, second], target: .png, processor: { input, _, temporaryDirectory, _, _ in
            if input == first {
                throw NSError(domain: "CeyloroTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "fixture failure"])
            }
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let output = temporaryDirectory.appendingPathComponent("output.png")
            try Data([0x02]).write(to: output)
            return [output]
        }) { snapshot in
            if snapshot.state == .completed {
                XCTAssertEqual(snapshot.outputs.count, 1)
                XCTAssertEqual(snapshot.failures.count, 1)
                completed.fulfill()
            }
        }

        _ = jobID
        wait(for: [completed], timeout: 2)
    }

    func testCollectionOfThreeFilesCreatesFolderWithStableNames() throws {
        let runner = JobRunner(maxConcurrentJobs: 1)
        let completed = expectation(description: "collection completed")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroCollection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("report.pdf")
        FileManager.default.createFile(atPath: input.path, contents: Data())

        runner.submit(inputs: [input], target: .png, outputDirectory: root, processor: { _, _, temporaryDirectory, _, _ in
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let files = try (1...3).map { index -> URL in
                let url = temporaryDirectory.appendingPathComponent("page\(index).png")
                try Data([UInt8(index)]).write(to: url)
                return url
            }
            return .collection(name: "report", files: files)
        }) { snapshot in
            guard snapshot.state == .completed else { return }
            XCTAssertEqual(snapshot.outputs.count, 1)
            let folder = snapshot.outputs[0]
            XCTAssertTrue(folder.hasDirectoryPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("report-01.png").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("report-03.png").path))
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
    }

    func testCollectionZipContainsOneParentFolder() throws {
        let runner = JobRunner(maxConcurrentJobs: 1)
        let completed = expectation(description: "zip completed")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroZip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("report.pdf")
        FileManager.default.createFile(atPath: input.path, contents: Data())

        runner.submit(inputs: [input], target: .png, outputDirectory: root, multiPageOutput: .zip, processor: { _, _, temporaryDirectory, _, _ in
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let first = temporaryDirectory.appendingPathComponent("first.png")
            let second = temporaryDirectory.appendingPathComponent("second.png")
            try Data([1]).write(to: first)
            try Data([2]).write(to: second)
            return .collection(name: "report", files: [first, second])
        }) { snapshot in
            guard snapshot.state == .completed else { return }
            XCTAssertEqual(snapshot.outputs.count, 1)
            XCTAssertEqual(snapshot.outputs[0].pathExtension, "zip")
            XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.outputs[0].path))
            completed.fulfill()
        }
        wait(for: [completed], timeout: 3)
    }

    func testConcurrentJobsWithSameBaseNameDoNotCollide() throws {
        let runner = JobRunner(maxConcurrentJobs: 2)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroCollision-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let input1 = root.appendingPathComponent("image.png")
        let input2 = root.appendingPathComponent("image.png") // same base name
        try Data("img1".utf8).write(to: input1)

        let exp1 = expectation(description: "job 1 finished")
        let exp2 = expectation(description: "job 2 finished")
        var out1: URL?
        var out2: URL?

        runner.submit(inputs: [input1], target: .jpg, outputDirectory: root, processor: { _, _, temp, _, _ in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let file = temp.appendingPathComponent("output.jpg")
            try Data("converted1".utf8).write(to: file)
            return .files([file])
        }) { snapshot in
            if snapshot.state == .completed {
                out1 = snapshot.outputs.first
                exp1.fulfill()
            } else if snapshot.state == .failed {
                XCTFail("Job 1 failed: \(snapshot.message), failures: \(snapshot.failures)")
                exp1.fulfill()
            }
        }

        runner.submit(inputs: [input2], target: .jpg, outputDirectory: root, processor: { _, _, temp, _, _ in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let file = temp.appendingPathComponent("output.jpg")
            try Data("converted2".utf8).write(to: file)
            return .files([file])
        }) { snapshot in
            if snapshot.state == .completed {
                out2 = snapshot.outputs.first
                exp2.fulfill()
            } else if snapshot.state == .failed {
                XCTFail("Job 2 failed: \(snapshot.message), failures: \(snapshot.failures)")
                exp2.fulfill()
            }
        }

        wait(for: [exp1, exp2], timeout: 5)
        XCTAssertNotNil(out1)
        XCTAssertNotNil(out2)
        XCTAssertNotEqual(out1, out2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out1!.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: out2!.path))
    }

    func testCustomCompressionSuffixAndExtensionAreApplied() throws {
        let runner = JobRunner(maxConcurrentJobs: 1)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroCompressionNaming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("proposal.docx")
        try Data("source".utf8).write(to: input)
        let completed = expectation(description: "compression naming completed")
        runner.submit(inputs: [input], target: .zip, outputDirectory: root, outputSuffix: "terkompres", outputExtension: "zip", processor: { _, _, temp, _, _ in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let output = temp.appendingPathComponent("output.zip")
            try Data("compressed".utf8).write(to: output)
            return [output]
        }) { snapshot in
            guard snapshot.state == .completed else { return }
            XCTAssertEqual(snapshot.outputs.first?.lastPathComponent, "proposal-terkompres.zip")
            completed.fulfill()
        }
        wait(for: [completed], timeout: 3)
    }

    // MARK: - B6 regression: dua job ZIP nama sama tidak bertabrakan dan tidak meninggalkan .staging
    func testConcurrentZipJobsSameNameDoNotCollide() throws {
        let runner = JobRunner(maxConcurrentJobs: 2)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroZipB6-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let input = root.appendingPathComponent("report.pdf")
        FileManager.default.createFile(atPath: input.path, contents: Data())

        let exp1 = expectation(description: "zip job 1 completed")
        let exp2 = expectation(description: "zip job 2 completed")
        var out1: URL?
        var out2: URL?

        // Job 1
        runner.submit(inputs: [input], target: .png, outputDirectory: root, multiPageOutput: .zip, processor: { _, _, temp, _, _ in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let page1 = temp.appendingPathComponent("page1.png")
            let page2 = temp.appendingPathComponent("page2.png")
            try Data("page1-job1".utf8).write(to: page1)
            try Data("page2-job1".utf8).write(to: page2)
            return .collection(name: "report", files: [page1, page2])
        }) { snapshot in
            if snapshot.state == .completed {
                out1 = snapshot.outputs.first
                exp1.fulfill()
            } else if snapshot.state == .failed {
                XCTFail("ZIP job 1 failed: \(snapshot.message)")
                exp1.fulfill()
            }
        }

        // Job 2 — same collection name, same output directory
        runner.submit(inputs: [input], target: .png, outputDirectory: root, multiPageOutput: .zip, processor: { _, _, temp, _, _ in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let page1 = temp.appendingPathComponent("page1.png")
            let page2 = temp.appendingPathComponent("page2.png")
            try Data("page1-job2".utf8).write(to: page1)
            try Data("page2-job2".utf8).write(to: page2)
            return .collection(name: "report", files: [page1, page2])
        }) { snapshot in
            if snapshot.state == .completed {
                out2 = snapshot.outputs.first
                exp2.fulfill()
            } else if snapshot.state == .failed {
                XCTFail("ZIP job 2 failed: \(snapshot.message)")
                exp2.fulfill()
            }
        }

        wait(for: [exp1, exp2], timeout: 10)

        // Kedua job harus menghasilkan ZIP yang berbeda
        XCTAssertNotNil(out1, "ZIP job 1 must produce output.")
        XCTAssertNotNil(out2, "ZIP job 2 must produce output.")
        XCTAssertNotEqual(out1, out2, "Concurrent ZIP jobs must not produce the same output path (B6).")
        XCTAssertTrue(FileManager.default.fileExists(atPath: out1!.path), "ZIP output 1 must exist.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: out2!.path), "ZIP output 2 must exist.")
        XCTAssertEqual(out1!.pathExtension, "zip")
        XCTAssertEqual(out2!.pathExtension, "zip")

        // Tidak boleh ada file .staging yang tertinggal (B6)
        let leftover = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".staging") }
        XCTAssertTrue(leftover.isEmpty, "No .staging files should remain after ZIP jobs complete (B6): \(leftover)")
    }

}
