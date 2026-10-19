import Foundation

public enum JobState: String, Sendable {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

public struct JobSnapshot: Sendable {
    public let id: UUID
    public let state: JobState
    public let progress: Double
    public let message: String
    public let outputs: [URL]

    public init(id: UUID, state: JobState, progress: Double, message: String, outputs: [URL] = []) {
        self.id = id
        self.state = state
        self.progress = progress
        self.message = message
        self.outputs = outputs
    }
}

public final class JobRunner {
    public typealias Processor = (_ input: URL, _ target: TargetFormat, _ temporaryDirectory: URL, _ progress: @escaping (Double) -> Void, _ isCancelled: @escaping () -> Bool) throws -> [URL]
    public typealias Update = (JobSnapshot) -> Void

    private let queue: OperationQueue
    private let fileManager: FileManager
    private var operations: [UUID: BlockOperation] = [:]
    private let lock = NSLock()

    public init(maxConcurrentJobs: Int = min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 4), fileManager: FileManager = .default) {
        self.queue = OperationQueue()
        self.queue.maxConcurrentOperationCount = maxConcurrentJobs
        self.fileManager = fileManager
    }

    @discardableResult
    public func submit(inputs: [URL], target: TargetFormat, outputDirectory: URL? = nil, processor: @escaping Processor, update: @escaping Update) -> UUID {
        let id = UUID()
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let self else { return }
            self.emit(JobSnapshot(id: id, state: .running, progress: 0, message: "Memproses…"), update: update)
            var outputs: [URL] = []
            let tempRoot = self.fileManager.temporaryDirectory.appendingPathComponent("Pomelo-\(id.uuidString)", isDirectory: true)
            do {
                try self.fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
                let total = max(inputs.count, 1)
                for (index, input) in inputs.enumerated() {
                    if operation?.isCancelled == true {
                        self.emit(JobSnapshot(id: id, state: .cancelled, progress: Double(index) / Double(total), message: "Dibatalkan"), update: update)
                        return
                    }
                    guard self.fileManager.isReadableFile(atPath: input.path) else {
                        throw NSError(domain: "Pomelo", code: 1, userInfo: [NSLocalizedDescriptionKey: "File tidak dapat dibaca: \(input.lastPathComponent)"])
                    }
                    let inputProgress = { (value: Double) in
                        let overall = (Double(index) + min(max(value, 0), 1)) / Double(total)
                        self.emit(JobSnapshot(id: id, state: .running, progress: overall, message: input.lastPathComponent, outputs: outputs), update: update)
                    }
                    let produced = try processor(input, target, tempRoot, inputProgress, { operation?.isCancelled == true })
                    let destinationFolder = outputDirectory ?? input.deletingLastPathComponent()
                    try self.fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                    for (outputIndex, temporaryURL) in produced.enumerated() {
                        let suffix = produced.count > 1 ? "\(outputIndex + 1)" : ""
                        let destination = OutputNaming().uniqueURL(for: input, target: target, in: destinationFolder, suffix: suffix, fileManager: self.fileManager)
                        try self.fileManager.moveItem(at: temporaryURL, to: destination)
                        outputs.append(destination)
                    }
                    inputProgress(1)
                }
                self.emit(JobSnapshot(id: id, state: .completed, progress: 1, message: "Selesai", outputs: outputs), update: update)
            } catch is CancellationError {
                self.emit(JobSnapshot(id: id, state: .cancelled, progress: 0, message: "Dibatalkan", outputs: outputs), update: update)
            } catch {
                if operation?.isCancelled == true {
                    self.emit(JobSnapshot(id: id, state: .cancelled, progress: 0, message: "Dibatalkan", outputs: outputs), update: update)
                } else {
                    self.emit(JobSnapshot(id: id, state: .failed, progress: 0, message: error.localizedDescription, outputs: outputs), update: update)
                }
            }
            try? self.fileManager.removeItem(at: tempRoot)
        }
        lock.lock()
        operations[id] = operation
        lock.unlock()
        emit(JobSnapshot(id: id, state: .queued, progress: 0, message: "Dalam antrean"), update: update)
        queue.addOperation(operation)
        return id
    }

    public func cancel(id: UUID) {
        lock.lock()
        let operation = operations[id]
        lock.unlock()
        operation?.cancel()
    }

    private func emit(_ snapshot: JobSnapshot, update: @escaping Update) {
        DispatchQueue.main.async { update(snapshot) }
    }
}
