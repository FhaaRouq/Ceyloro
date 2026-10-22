import CeyloroCore
import Foundation
import PDFKit

final class DocumentConverter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func supportedTargets(for files: [URL], candidates: [TargetFormat], libreOfficeURL: URL?, pandocURL: URL?) -> [TargetFormat] {
        guard !files.isEmpty,
              files.allSatisfy({ FileFormat.detect(url: $0).kind == .document && fileManager.isReadableFile(atPath: $0.path) }) else { return [] }
        let policy = DocumentConversionPolicy()
        return candidates.filter { target in
            files.map(FileFormat.detect(url:)).allSatisfy { source in
                guard policy.targets(for: source).contains(target),
                      canConvert(source: source, target: target, libreOfficeURL: libreOfficeURL, pandocURL: pandocURL) else { return false }
                if source.kind == .pdf && target == .docx {
                    return hasExtractableText(at: files[0])
                }
                return true
            }
        }
    }

    func convert(input: URL, target: TargetFormat, temporaryDirectory: URL, libreOfficeURL: URL?, pandocURL: URL?, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool, timeout: TimeInterval = 180) throws -> ConversionResult {
        let source = FileFormat.detect(url: input)
        guard DocumentConversionPolicy().targets(for: source).contains(target),
              fileManager.isReadableFile(atPath: input.path),
              canConvert(source: source, target: target, libreOfficeURL: libreOfficeURL, pandocURL: pandocURL) else {
            throw ConversionError.unsupportedConversion
        }
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }
        if isCancelled() { throw CancellationError() }

        if source.kind == .pdf && target == .docx {
            guard let pandocURL,
                  let document = PDFDocument(url: input),
                  !document.isLocked,
                  let text = extractText(from: document),
                  !text.isEmpty else { throw ConversionError.noText }
            let textInput = temporaryDirectory.appendingPathComponent("input.txt")
            try text.write(to: textInput, atomically: true, encoding: .utf8)
            let output = temporaryDirectory.appendingPathComponent("output.\(target.fileExtension)")
            try runPandoc(input: textInput, from: "plain", output: output, target: target, executable: pandocURL, temporaryDirectory: temporaryDirectory, timeout: timeout, isCancelled: isCancelled)
            let outputSize = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard fileManager.fileExists(atPath: output.path), outputSize > 0 else { throw ConversionError.encodingFailed }
            progress(1)
            return .files([output])
        }

        let safeExtension = source.fileExtension.isEmpty ? "bin" : source.fileExtension
        let safeInput = temporaryDirectory.appendingPathComponent("input.\(safeExtension)")
        try fileManager.copyItem(at: input, to: safeInput)
        progress(0.08)

        let output: URL
        if needsPandocPDF(source: source, target: target) {
            guard let pandocURL, let libreOfficeURL else { throw ConversionError.unsupportedConversion }
            let intermediate = temporaryDirectory.appendingPathComponent("intermediate.docx")
            try runPandoc(input: safeInput, source: source, output: intermediate, target: .docx, executable: pandocURL, temporaryDirectory: temporaryDirectory, timeout: timeout, isCancelled: isCancelled)
            progress(0.55)
            output = temporaryDirectory.appendingPathComponent("output.pdf")
            try runLibreOffice(input: intermediate, target: .pdf, output: output, executable: libreOfficeURL, temporaryDirectory: temporaryDirectory, timeout: timeout, isCancelled: isCancelled)
        } else if usesPandoc(source: source, target: target) {
            guard let pandocURL else { throw ConversionError.unsupportedConversion }
            output = temporaryDirectory.appendingPathComponent("output.\(target.fileExtension)")
            try runPandoc(input: safeInput, source: source, output: output, target: target, executable: pandocURL, temporaryDirectory: temporaryDirectory, timeout: timeout, isCancelled: isCancelled)
        } else {
            guard let libreOfficeURL else { throw ConversionError.unsupportedConversion }
            output = temporaryDirectory.appendingPathComponent("output.\(target.fileExtension)")
            try runLibreOffice(input: safeInput, target: target, output: output, executable: libreOfficeURL, temporaryDirectory: temporaryDirectory, timeout: timeout, isCancelled: isCancelled)
        }

        let outputSize = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileManager.fileExists(atPath: output.path), outputSize > 0 else {
            throw ConversionError.encodingFailed
        }
        if target == .pdf {
            let header = Data(try Data(contentsOf: output).prefix(5))
            guard String(data: header, encoding: .ascii) == "%PDF-" else { throw ConversionError.encodingFailed }
        }
        progress(1)
        return .files([output])
    }

    private func canConvert(source: FileFormat, target: TargetFormat, libreOfficeURL: URL?, pandocURL: URL?) -> Bool {
        if needsPandocPDF(source: source, target: target) { return pandocURL != nil && libreOfficeURL != nil }
        if source.kind == .pdf && target == .docx { return pandocURL != nil }
        if usesPandoc(source: source, target: target) { return pandocURL != nil }
        return libreOfficeURL != nil
    }

    private func usesPandoc(source: FileFormat, target: TargetFormat) -> Bool {
        switch (source.fileExtension, target) {
        case ("docx", .md), ("docx", .html), ("docx", .txt): return true
        case ("md", .docx), ("html", .docx), ("txt", .docx): return true
        default: return false
        }
    }

    private func hasExtractableText(at url: URL) -> Bool {
        guard let document = PDFDocument(url: url), !document.isLocked else { return false }
        return extractText(from: document) != nil
    }

    private func extractText(from document: PDFDocument) -> String? {
        let pages = (0..<document.pageCount).compactMap { index in
            document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard !pages.isEmpty else { return nil }
        return pages.joined(separator: "\n\n") + "\n"
    }

    private func needsPandocPDF(source: FileFormat, target: TargetFormat) -> Bool {
        target == .pdf && ["md", "html", "txt"].contains(source.fileExtension)
    }

    private func runLibreOffice(input: URL, target: TargetFormat, output: URL, executable: URL, temporaryDirectory: URL, timeout: TimeInterval, isCancelled: @escaping () -> Bool) throws {
        let profile = temporaryDirectory.appendingPathComponent("lo-profile", isDirectory: true)
        try fileManager.createDirectory(at: profile, withIntermediateDirectories: true)
        let profileURL = profile.absoluteString.hasPrefix("file://") ? profile.absoluteString : "file://\(profile.path)"
        let arguments = ["--headless", "--nologo", "--nodefault", "--nofirststartwizard", "--nolockcheck", "-env:UserInstallation=\(profileURL)", "--convert-to", target.fileExtension, "--outdir", temporaryDirectory.path, input.path]
        try runProcess(executable: executable, arguments: arguments, timeout: timeout, isCancelled: isCancelled)
        let generated = temporaryDirectory.appendingPathComponent(input.deletingPathExtension().lastPathComponent + "." + target.fileExtension)
        if generated != output { try? fileManager.removeItem(at: output); try fileManager.moveItem(at: generated, to: output) }
    }

    private func runPandoc(input: URL, source: FileFormat, output: URL, target: TargetFormat, executable: URL, temporaryDirectory: URL, timeout: TimeInterval, isCancelled: @escaping () -> Bool) throws {
        try runPandoc(input: input, from: pandocInputFormat(for: source), output: output, target: target, executable: executable, temporaryDirectory: temporaryDirectory, timeout: timeout, isCancelled: isCancelled)
    }

    private func runPandoc(input: URL, from sourceFormat: String, output: URL, target: TargetFormat, executable: URL, temporaryDirectory: URL, timeout: TimeInterval, isCancelled: @escaping () -> Bool) throws {
        let targetFormat = pandocOutputFormat(for: target)
        let arguments = ["--from", sourceFormat, "--to", targetFormat, "--output", output.path, input.path]
        try runProcess(executable: executable, arguments: arguments, timeout: timeout, isCancelled: isCancelled)
    }

    private func pandocInputFormat(for source: FileFormat) -> String {
        switch source.fileExtension {
        case "md": return "markdown"
        case "html": return "html"
        case "txt": return "plain"
        default: return source.fileExtension
        }
    }

    private func pandocOutputFormat(for target: TargetFormat) -> String {
        switch target {
        case .md: return "gfm"
        case .html: return "html"
        case .txt: return "plain"
        default: return target.fileExtension
        }
    }

    private func runProcess(executable: URL, arguments: [String], timeout: TimeInterval, isCancelled: @escaping () -> Bool) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if isCancelled() {
                process.terminate()
                process.waitUntilExit()
                throw CancellationError()
            }
            if Date() >= deadline {
                process.terminate()
                process.waitUntilExit()
                throw ConversionError.documentTimeout
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard process.terminationStatus == 0 else { throw ConversionError.documentEngineFailed }
    }
}
