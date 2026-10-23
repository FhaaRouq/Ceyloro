import Foundation

public enum JobState: String, Sendable {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

public struct JobFailure: Sendable, Equatable {
    public let input: URL
    public let message: String

    public init(input: URL, message: String) {
        self.input = input
        self.message = message
    }
}

public enum ConversionResult: ExpressibleByArrayLiteral, Sendable {
    case files([URL])
    case collection(name: String, files: [URL])

    public init(arrayLiteral elements: URL...) {
        self = .files(elements)
    }

    public var first: URL? {
        switch self {
        case let .files(files), let .collection(_, files):
            return files.first
        }
    }
}

public enum MultiPageOutput: String, Codable, Sendable {
    case folder
    case zip
}

public struct JobSnapshot: Sendable {
    public let id: UUID
    public let state: JobState
    public let progress: Double
    public let message: String
    public let outputs: [URL]
    public let failures: [JobFailure]

    public init(id: UUID, state: JobState, progress: Double, message: String, outputs: [URL] = [], failures: [JobFailure] = []) {
        self.id = id
        self.state = state
        self.progress = progress
        self.message = message
        self.outputs = outputs
        self.failures = failures
    }
}

/// Coordinates concurrent file conversion and merge jobs with bounded parallelism.
///
/// ### Threading Model & Concurrency Invariants
/// - **Thread Safety**: `JobRunner` is safe to call from any thread (UI main thread or background worker threads).
/// - **State Synchronization**: Access to the mutable state properties (`operations` and `updates`) is strictly
///   guarded by an internal `NSLock` (`lock`). Callers never hold locks across asynchronous operations.
/// - **Job Execution**: Tasks are queued and executed asynchronously on an internal `OperationQueue` with bounded
///   concurrency (`maxConcurrentOperationCount`), ensuring disk and CPU resources are not saturated.
/// - **Progress & Snapshot Dispatch**: All `Update` callback invocations (`JobSnapshot`) are guaranteed to be
///   dispatched asynchronously onto `DispatchQueue.main` so UI observers (e.g. progress bars, status items) can
///   update AppKit views without additional thread hops.
/// - **Terminal State Cleanup**: When a job completes, fails, or is cancelled, its corresponding entries in
///   `operations` and `updates` are purged under lock inside `emit` once the final snapshot is handed to the main thread.
public final class JobRunner {
    public typealias Processor = (_ input: URL, _ target: TargetFormat, _ temporaryDirectory: URL, _ progress: @escaping (Double) -> Void, _ isCancelled: @escaping () -> Bool) throws -> ConversionResult
    public typealias MergeProcessor = (_ inputs: [URL], _ temporaryFile: URL, _ options: PDFMergeOptions, _ progress: @escaping (Double) -> Void, _ isCancelled: @escaping () -> Bool) throws -> URL
    public typealias Update = (JobSnapshot) -> Void

    private let queue: OperationQueue
    private let fileManager: FileManager

    // Guarded by `lock`
    private var operations: [UUID: BlockOperation] = [:]
    // Guarded by `lock`
    private var updates: [UUID: Update] = [:]
    private let lock = NSLock()

    /// Initializes a job runner with bounded concurrency.
    /// - Parameters:
    ///   - maxConcurrentJobs: Maximum operations to run concurrently. Clamped between 1 and activeProcessorCount (up to 4).
    ///   - fileManager: FileManager instance for file moving and directory operations.
    public init(maxConcurrentJobs: Int = min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 4), fileManager: FileManager = .default) {
        self.queue = OperationQueue()
        self.queue.maxConcurrentOperationCount = maxConcurrentJobs
        self.fileManager = fileManager
    }

    /// Checks if any submitted jobs are currently executing or queued.
    /// Thread-safe: Acquires `lock` to inspect active operations.
    public var hasActiveJobs: Bool {
        lock.lock()
        defer { lock.unlock() }
        return operations.values.contains { !$0.isFinished }
    }

    /// Cancels all queued and running jobs.
    /// Thread-safe: Snapshot of active IDs is taken under `lock` before cancellation.
    public func cancelAll() {
        lock.lock()
        let ids = Array(operations.keys)
        lock.unlock()
        ids.forEach { cancel(id: $0) }
    }

    /// Submits a batch file conversion job.
    /// Thread-safe: Registers operation and updates under `lock` before queueing onto background `OperationQueue`.
    /// - Parameters:
    ///   - inputs: Source file URLs to convert.
    ///   - target: Desired target file format.
    ///   - outputDirectory: Optional destination directory; defaults to the input files' directory.
    ///   - multiPageOutput: Formatting strategy when multi-page outputs are produced (.folder or .zip).
    ///   - processor: Heavy conversion callback executed on worker thread.
    ///   - update: Status callback delivered on `DispatchQueue.main`.
    /// - Returns: Unique UUID identifying this job.
    @discardableResult
    public func submit(inputs: [URL], target: TargetFormat, outputDirectory: URL? = nil, multiPageOutput: MultiPageOutput = .folder, outputSuffix: String = "", outputExtension: String? = nil, processor: @escaping Processor, update: @escaping Update) -> UUID {
        let id = UUID()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let self else { return }
            if operation?.isCancelled == true {
                self.emit(JobSnapshot(id: id, state: .cancelled, progress: 0, message: "Dibatalkan"), update: update)
                return
            }

            var outputs: [URL] = []
            var failures: [JobFailure] = []
            let tempRoot = self.fileManager.temporaryDirectory.appendingPathComponent("Ceyloro-\(id.uuidString)", isDirectory: true)

            do {
                try self.fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
                defer { try? self.fileManager.removeItem(at: tempRoot) }

                self.emit(JobSnapshot(id: id, state: .running, progress: 0, message: "Memproses…"), update: update)
                let total = max(inputs.count, 1)

                for (index, input) in inputs.enumerated() {
                    if operation?.isCancelled == true {
                        try? self.fileManager.removeItem(at: tempRoot)
                        self.emit(JobSnapshot(id: id, state: .cancelled, progress: Double(index) / Double(total), message: "Dibatalkan", outputs: outputs, failures: failures), update: update)
                        return
                    }

                    do {
                        guard self.fileManager.isReadableFile(atPath: input.path) else {
                            throw NSError(domain: "Ceyloro", code: 1, userInfo: [NSLocalizedDescriptionKey: "File tidak dapat dibaca: \(input.lastPathComponent)"])
                        }

                let inputProgress = { (value: Double) in
                    let overall = (Double(index) + min(max(value, 0), 1)) / Double(total)
                    let msg = total > 1 ? "\(input.lastPathComponent) → \(target.title) (\(index + 1)/\(total))" : "\(input.lastPathComponent) → \(target.title)"
                    self.emit(JobSnapshot(id: id, state: .running, progress: overall, message: msg, outputs: outputs, failures: failures), update: update)
                }
                        let fileTemp = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
                        let produced = try processor(input, target, fileTemp, inputProgress, { operation?.isCancelled == true })
                        if operation?.isCancelled == true { throw CancellationError() }
                        let destinationFolder = outputDirectory ?? input.deletingLastPathComponent()
                        try self.fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

                        let resultURLs = try self.commit(produced, input: input, target: target, destinationFolder: destinationFolder, multiPageOutput: multiPageOutput, temporaryRoot: tempRoot, operation: operation, outputSuffix: outputSuffix, outputExtension: outputExtension)
                        outputs.append(contentsOf: resultURLs)
                        inputProgress(1)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        failures.append(JobFailure(input: input, message: error.localizedDescription))
                        let overall = Double(index + 1) / Double(total)
                        self.emit(JobSnapshot(id: id, state: .running, progress: overall, message: "Gagal: \(input.lastPathComponent)", outputs: outputs, failures: failures), update: update)
                    }
                }

                let state: JobState = outputs.isEmpty && !failures.isEmpty ? .failed : .completed
                let message: String
                if failures.isEmpty {
                    message = "Selesai"
                } else if outputs.isEmpty {
                    message = "Semua file gagal diproses"
                } else {
                    message = "Selesai dengan \(failures.count) file gagal"
                }
                try? self.fileManager.removeItem(at: tempRoot)
                self.emit(JobSnapshot(id: id, state: state, progress: 1, message: message, outputs: outputs, failures: failures), update: update)
            } catch is CancellationError {
                try? self.fileManager.removeItem(at: tempRoot)
                self.emit(JobSnapshot(id: id, state: .cancelled, progress: 0, message: "Dibatalkan", outputs: outputs, failures: failures), update: update)
            } catch {
                let failure = JobFailure(input: inputs.first ?? URL(fileURLWithPath: ""), message: error.localizedDescription)
                failures.append(failure)
                try? self.fileManager.removeItem(at: tempRoot)
                self.emit(JobSnapshot(id: id, state: .failed, progress: 0, message: error.localizedDescription, outputs: outputs, failures: failures), update: update)
            }
        }

        lock.lock()
        operations[id] = operation
        updates[id] = update
        lock.unlock()
        emit(JobSnapshot(id: id, state: .queued, progress: 0, message: "Dalam antrean"), update: update)
        queue.addOperation(operation)
        return id
    }

    /// Cancels a specific job by UUID.
    /// Thread-safe: Retrieves operation and updates under `lock`. If job was still queued,
    /// emits a cancellation snapshot immediately on the main thread.
    public func cancel(id: UUID) {
        lock.lock()
        let operation = operations[id]
        let update = updates[id]
        let isQueued = operation.map { !$0.isExecuting && !$0.isFinished } ?? false
        lock.unlock()

        guard let operation else { return }
        operation.cancel()
        if isQueued, let update {
            emit(JobSnapshot(id: id, state: .cancelled, progress: 0, message: "Dibatalkan"), update: update)
        }
    }

    @discardableResult
    public func submitMerge(inputsInOrder: [URL], options: PDFMergeOptions, outputName: String, outputDirectory: URL? = nil, processor: @escaping MergeProcessor, update: @escaping Update) -> UUID {
        let id = UUID()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let self else { return }
            if operation?.isCancelled == true {
                self.emit(JobSnapshot(id: id, state: .cancelled, progress: 0, message: "Dibatalkan"), update: update)
                return
            }

            let tempRoot = self.fileManager.temporaryDirectory.appendingPathComponent("Ceyloro-\(id.uuidString)", isDirectory: true)
            do {
                try self.fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
                defer { try? self.fileManager.removeItem(at: tempRoot) }
                self.emit(JobSnapshot(id: id, state: .running, progress: 0, message: "Membuat PDF…"), update: update)
                let temporaryFile = tempRoot.appendingPathComponent("output.pdf")
                let result = try processor(inputsInOrder, temporaryFile, options, { value in
                    self.emit(JobSnapshot(id: id, state: .running, progress: min(max(value, 0), 1), message: "Membuat PDF…"), update: update)
                }, { operation?.isCancelled == true })
                if operation?.isCancelled == true { throw CancellationError() }
                let folder = outputDirectory ?? inputsInOrder.first?.deletingLastPathComponent() ?? self.fileManager.homeDirectoryForCurrentUser
                try self.fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = OutputNaming().reserveUniqueURL(baseName: outputName, fileExtension: "pdf", in: folder, fileManager: self.fileManager)
                do {
                    try self.moveSafely(from: result, to: destination, overwritePlaceholder: true)
                    self.emit(JobSnapshot(id: id, state: .completed, progress: 1, message: "Selesai", outputs: [destination]), update: update)
                } catch {
                    try? self.fileManager.removeItem(at: destination)
                    throw error
                }
            } catch is CancellationError {
                try? self.fileManager.removeItem(at: tempRoot)
                self.emit(JobSnapshot(id: id, state: .cancelled, progress: 0, message: "Dibatalkan"), update: update)
            } catch {
                let input = inputsInOrder.first ?? URL(fileURLWithPath: "")
                let failure = JobFailure(input: input, message: error.localizedDescription)
                try? self.fileManager.removeItem(at: tempRoot)
                self.emit(JobSnapshot(id: id, state: .failed, progress: 0, message: error.localizedDescription, failures: [failure]), update: update)
            }
        }

        lock.lock()
        operations[id] = operation
        updates[id] = update
        lock.unlock()
        emit(JobSnapshot(id: id, state: .queued, progress: 0, message: "Dalam antrean"), update: update)
        queue.addOperation(operation)
        return id
    }

    private func commit(_ result: ConversionResult, input: URL, target: TargetFormat, destinationFolder: URL, multiPageOutput: MultiPageOutput, temporaryRoot: URL, operation: BlockOperation?, outputSuffix: String, outputExtension: String?) throws -> [URL] {
        let naming = OutputNaming()
        let temporaryFiles: [URL]
        let collectionName: String?
        switch result {
        case let .files(files):
            temporaryFiles = files
            collectionName = nil
        case let .collection(name, files):
            temporaryFiles = files
            collectionName = name
        }

        guard temporaryFiles.count > 1, let collectionName else {
            var committed: [URL] = []
            for temporaryURL in temporaryFiles {
                if operation?.isCancelled == true { throw CancellationError() }
                let destination: URL
                if let outputExtension {
                    destination = naming.reserveUniqueURL(baseName: OutputNaming.strippedBaseName(for: input), fileExtension: outputExtension, in: destinationFolder, suffix: outputSuffix, fileManager: fileManager)
                } else {
                    destination = naming.reserveUniqueURL(for: input, target: target, in: destinationFolder, suffix: outputSuffix, fileManager: fileManager)
                }
                do {
                    try moveSafely(from: temporaryURL, to: destination, overwritePlaceholder: true)
                    committed.append(destination)
                } catch {
                    try? fileManager.removeItem(at: destination)
                    throw error
                }
            }
            return committed
        }

        switch multiPageOutput {
        case .folder:
            let folder = naming.reserveUniqueFolderURL(baseName: collectionName, in: destinationFolder, fileManager: fileManager)
            do {
                for (index, temporaryURL) in temporaryFiles.enumerated() {
                    if operation?.isCancelled == true { throw CancellationError() }
                    let fileName = naming.pageFileName(baseName: collectionName, index: index, total: temporaryFiles.count, fileExtension: target.fileExtension)
                    let destination = folder.appendingPathComponent(fileName)
                    try moveSafely(from: temporaryURL, to: destination)
                }
                return [folder]
            } catch {
                try? fileManager.removeItem(at: folder)
                throw error
            }
        case .zip:
            let staging = temporaryRoot.appendingPathComponent("zip-\(UUID().uuidString)", isDirectory: true)
            let folder = staging.appendingPathComponent(collectionName, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for (index, temporaryURL) in temporaryFiles.enumerated() {
                if operation?.isCancelled == true { throw CancellationError() }
                let fileName = naming.pageFileName(baseName: collectionName, index: index, total: temporaryFiles.count, fileExtension: target.fileExtension)
                try moveSafely(from: temporaryURL, to: folder.appendingPathComponent(fileName))
            }
            // B6: reserveUniqueURL menciptakan placeholder atomik (O_CREAT | O_EXCL),
            // lalu ditto menulis ke path .staging di sampingnya.
            // Setelah ditto sukses, move atomik placeholder → ZIP final.
            // Placeholder dihapus HANYA setelah move berhasil, sehingga tidak ada jendela
            // di mana dua job bisa mendapat path yang sama.
            let zipURL = naming.reserveUniqueURL(baseName: collectionName, fileExtension: "zip", in: destinationFolder, fileManager: fileManager)
            let zipStagingURL = URL(fileURLWithPath: zipURL.path + ".staging")
            do {
                if operation?.isCancelled == true { throw CancellationError() }
                try archive(folder: folder, to: zipStagingURL, operation: operation)
                // Atomik: hapus placeholder, pindahkan staging ke final
                try? fileManager.removeItem(at: zipURL)
                try moveSafely(from: zipStagingURL, to: zipURL)
                return [zipURL]
            } catch {
                try? fileManager.removeItem(at: zipStagingURL)
                try? fileManager.removeItem(at: zipURL)
                throw error
            }
        }
    }

    private func archive(folder: URL, to zipURL: URL, operation: BlockOperation?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", folder.path, zipURL.path]
        try process.run()
        while process.isRunning {
            if operation?.isCancelled == true {
                process.terminate()
                process.waitUntilExit()
                try? fileManager.removeItem(at: zipURL)
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard process.terminationStatus == 0 else {
            try? fileManager.removeItem(at: zipURL)
            throw NSError(domain: "Ceyloro", code: 2, userInfo: [NSLocalizedDescriptionKey: "ZIP gagal dibuat."])
        }
    }

    // Keep an existing destination intact if a cross-volume copy fails.
    // The caller already chooses unique destination names, so deleting the
    // destination here could destroy an unrelated file in a race.
    func moveSafely(from source: URL, to destination: URL, overwritePlaceholder: Bool = false) throws {
        if overwritePlaceholder && fileManager.fileExists(atPath: destination.path) {
            if let _ = try? fileManager.replaceItemAt(destination, withItemAt: source) {
                return
            }
        }
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch let moveError {
            do {
                try fileManager.copyItem(at: source, to: destination)
                try fileManager.removeItem(at: source)
            } catch {
                throw moveError
            }
        }
    }

    private func emit(_ snapshot: JobSnapshot, update: @escaping Update) {
        DispatchQueue.main.async { [weak self] in
            update(snapshot)
            guard snapshot.state == .completed || snapshot.state == .failed || snapshot.state == .cancelled else { return }
            self?.lock.lock()
            self?.operations.removeValue(forKey: snapshot.id)
            self?.updates.removeValue(forKey: snapshot.id)
            self?.lock.unlock()
        }
    }
}
