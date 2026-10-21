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

public final class JobRunner {
    public typealias Processor = (_ input: URL, _ target: TargetFormat, _ temporaryDirectory: URL, _ progress: @escaping (Double) -> Void, _ isCancelled: @escaping () -> Bool) throws -> ConversionResult
    public typealias MergeProcessor = (_ inputs: [URL], _ temporaryFile: URL, _ options: PDFMergeOptions, _ progress: @escaping (Double) -> Void, _ isCancelled: @escaping () -> Bool) throws -> URL
    public typealias Update = (JobSnapshot) -> Void

    private let queue: OperationQueue
    private let fileManager: FileManager
    private var operations: [UUID: BlockOperation] = [:]
    private var updates: [UUID: Update] = [:]
    private let lock = NSLock()

    public init(maxConcurrentJobs: Int = min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 4), fileManager: FileManager = .default) {
        self.queue = OperationQueue()
        self.queue.maxConcurrentOperationCount = maxConcurrentJobs
        self.fileManager = fileManager
    }

    public var hasActiveJobs: Bool {
        lock.lock()
        defer { lock.unlock() }
        return operations.values.contains { !$0.isFinished }
    }

    public func cancelAll() {
        lock.lock()
        let ids = Array(operations.keys)
        lock.unlock()
        ids.forEach { cancel(id: $0) }
    }

    @discardableResult
    public func submit(inputs: [URL], target: TargetFormat, outputDirectory: URL? = nil, multiPageOutput: MultiPageOutput = .folder, processor: @escaping Processor, update: @escaping Update) -> UUID {
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
                            self.emit(JobSnapshot(id: id, state: .running, progress: overall, message: input.lastPathComponent, outputs: outputs, failures: failures), update: update)
                        }
                        let fileTemp = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
                        let produced = try processor(input, target, fileTemp, inputProgress, { operation?.isCancelled == true })
                        if operation?.isCancelled == true { throw CancellationError() }
                        let destinationFolder = outputDirectory ?? input.deletingLastPathComponent()
                        try self.fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

                        let resultURLs = try self.commit(produced, input: input, target: target, destinationFolder: destinationFolder, multiPageOutput: multiPageOutput, temporaryRoot: tempRoot, operation: operation)
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
                let destination = OutputNaming().uniqueURL(baseName: outputName, fileExtension: "pdf", in: folder, fileManager: self.fileManager)
                try self.moveSafely(from: result, to: destination)
                self.emit(JobSnapshot(id: id, state: .completed, progress: 1, message: "Selesai", outputs: [destination]), update: update)
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

    private func commit(_ result: ConversionResult, input: URL, target: TargetFormat, destinationFolder: URL, multiPageOutput: MultiPageOutput, temporaryRoot: URL, operation: BlockOperation?) throws -> [URL] {
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
                let destination = naming.uniqueURL(for: input, target: target, in: destinationFolder, fileManager: fileManager)
                try moveSafely(from: temporaryURL, to: destination)
                committed.append(destination)
            }
            return committed
        }

        switch multiPageOutput {
        case .folder:
            let folder = naming.uniqueFolderURL(baseName: collectionName, in: destinationFolder, fileManager: fileManager)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
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
            let staging = temporaryRoot.appendingPathComponent("zip", isDirectory: true)
            let folder = staging.appendingPathComponent(collectionName, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let zipURL = naming.uniqueURL(baseName: collectionName, fileExtension: "zip", in: destinationFolder, fileManager: fileManager)
            do {
                for (index, temporaryURL) in temporaryFiles.enumerated() {
                    if operation?.isCancelled == true { throw CancellationError() }
                    let fileName = naming.pageFileName(baseName: collectionName, index: index, total: temporaryFiles.count, fileExtension: target.fileExtension)
                    try moveSafely(from: temporaryURL, to: folder.appendingPathComponent(fileName))
                }
                try archive(folder: folder, to: zipURL, operation: operation)
                return [zipURL]
            } catch {
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

    private func moveSafely(from source: URL, to destination: URL) throws {
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch let moveError {
            do {
                try fileManager.copyItem(at: source, to: destination)
                try fileManager.removeItem(at: source)
            } catch {
                try? fileManager.removeItem(at: destination)
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
