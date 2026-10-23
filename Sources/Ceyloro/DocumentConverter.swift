import CeyloroCore
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

final class DocumentConverter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func supportedTargets(for files: [URL], candidates: [TargetFormat], libreOfficeURL: URL?, pandocURL: URL?) -> [TargetFormat] {
        guard !files.isEmpty else { return [] }
        let policy = DocumentConversionPolicy()
        // Izinkan kind .document dan .pdf — PDF memiliki target DOCX via policy (temuan A5).
        // Kind lain (image, audio, dll.) tidak ditangani oleh converter ini.
        let allowedKinds: Set<FileFormat.Kind> = [.document, .pdf]
        guard files.allSatisfy({
            let fmt = FileFormat.detect(url: $0)
            return allowedKinds.contains(fmt.kind) && fileManager.isReadableFile(atPath: $0.path)
        }) else { return [] }
        return candidates.filter { target in
            files.allSatisfy { url in
                let source = FileFormat.detect(url: url)
                guard policy.targets(for: source).contains(target),
                      canConvert(source: source, target: target, libreOfficeURL: libreOfficeURL, pandocURL: pandocURL) else { return false }
                // Periksa setiap PDF secara individual — jangan pakai files[0] sebagai proxy
                // untuk seluruh batch (temuan A5, bug batch).
                if source.kind == .pdf && target == .docx {
                    return hasExtractableText(at: url)
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
        if isCancelled() { throw CancellationError() }

        if isSpreadsheet(source), target == .csv {
            return try convertSpreadsheetToCSV(input: input, temporaryDirectory: temporaryDirectory, libreOfficeURL: libreOfficeURL, progress: progress, isCancelled: isCancelled, timeout: timeout)
        }

        if isPresentation(source), target == .png {
            return try convertPresentationToPNG(input: input, temporaryDirectory: temporaryDirectory, libreOfficeURL: libreOfficeURL, progress: progress, isCancelled: isCancelled, timeout: timeout)
        }

        if source.kind == .pdf && target == .docx {
            guard let pandocURL,
                  let document = PDFDocument(url: input),
                  !document.isLocked,
                  let text = extractText(from: document),
                  !text.isEmpty else { throw ConversionError.noText }
            let textInput = temporaryDirectory.appendingPathComponent("input.txt")
            try text.write(to: textInput, atomically: true, encoding: .utf8)
            let output = temporaryDirectory.appendingPathComponent("output.\(target.fileExtension)")
            try runPandoc(input: textInput, from: "markdown", output: output, target: target, executable: pandocURL, temporaryDirectory: temporaryDirectory, timeout: timeout, isCancelled: isCancelled)
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

    private func isSpreadsheet(_ source: FileFormat) -> Bool {
        ["xls", "xlsx", "ods"].contains(source.fileExtension)
    }

    private func isPresentation(_ source: FileFormat) -> Bool {
        ["ppt", "pptx", "odp"].contains(source.fileExtension)
    }

    private func convertSpreadsheetToCSV(input: URL, temporaryDirectory: URL, libreOfficeURL: URL?, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool, timeout: TimeInterval) throws -> ConversionResult {
        guard let libreOfficeURL else { throw ConversionError.unsupportedConversion }
        let outputDirectory = temporaryDirectory.appendingPathComponent("csv", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let scriptURL = temporaryDirectory.appendingPathComponent("export-sheets.py")
        try spreadsheetExportScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try runSpreadsheetScript(input: input, outputDirectory: outputDirectory, baseName: OutputNaming.strippedBaseName(for: input), scriptURL: scriptURL, libreOfficeURL: libreOfficeURL, temporaryDirectory: temporaryDirectory, timeout: timeout, isCancelled: isCancelled)
        let files = try fileManager.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "csv" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !files.isEmpty, files.allSatisfy({ ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 }) else {
            throw ConversionError.encodingFailed
        }
        progress(1)
        return .collection(name: OutputNaming.strippedBaseName(for: input), files: files)
    }

    private func convertPresentationToPNG(input: URL, temporaryDirectory: URL, libreOfficeURL: URL?, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool, timeout: TimeInterval) throws -> ConversionResult {
        guard let libreOfficeURL else { throw ConversionError.unsupportedConversion }
        let safeInput = temporaryDirectory.appendingPathComponent("presentation.\(input.pathExtension.lowercased())")
        try fileManager.copyItem(at: input, to: safeInput)
        let pdfURL = temporaryDirectory.appendingPathComponent("presentation.pdf")
        try runLibreOffice(input: safeInput, target: .pdf, output: pdfURL, executable: libreOfficeURL, temporaryDirectory: temporaryDirectory, timeout: timeout, isCancelled: isCancelled)
        guard let document = PDFDocument(url: pdfURL), !document.isLocked, document.pageCount > 0 else { throw ConversionError.invalidInput }
        let outputDirectory = temporaryDirectory.appendingPathComponent("slides", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var outputs: [URL] = []
        for index in 0..<document.pageCount {
            if isCancelled() { throw CancellationError() }
            try autoreleasepool {
                guard let page = document.page(at: index), let image = renderSlide(page: page) else { throw ConversionError.encodingFailed }
                let name = OutputNaming().pageFileName(baseName: OutputNaming.strippedBaseName(for: input), index: index, total: document.pageCount, fileExtension: "png")
                let output = outputDirectory.appendingPathComponent(name)
                guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw ConversionError.encodingFailed }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw ConversionError.encodingFailed }
                outputs.append(output)
            }
            progress(0.1 + 0.9 * Double(index + 1) / Double(document.pageCount))
        }
        return .collection(name: OutputNaming.strippedBaseName(for: input), files: outputs)
    }

    private func renderSlide(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(2.0, 2400.0 / max(bounds.width, bounds.height, 1))
        let width = max(Int((bounds.width * scale).rounded()), 1)
        let height = max(Int((bounds.height * scale).rounded()), 1)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }

    private func runSpreadsheetScript(input: URL, outputDirectory: URL, baseName: String, scriptURL: URL, libreOfficeURL: URL, temporaryDirectory: URL, timeout: TimeInterval, isCancelled: @escaping () -> Bool) throws {
        let profile = temporaryDirectory.appendingPathComponent("lo-calc-profile", isDirectory: true)
        try fileManager.createDirectory(at: profile, withIntermediateDirectories: true)
        let profileURL = profile.absoluteString.hasPrefix("file://") ? profile.absoluteString : "file://\(profile.path)"
        let port = 20000 + Int.random(in: 0..<2000)
        let office = Process()
        office.executableURL = libreOfficeURL
        office.arguments = ["--headless", "--nologo", "--nodefault", "--nofirststartwizard", "--nolockcheck", "--norestore", "-env:UserInstallation=\(profileURL)", "--accept=socket,host=127.0.0.1,port=\(port);urp;StarOffice.ComponentContext"]
        office.standardOutput = FileHandle.nullDevice
        office.standardError = FileHandle.nullDevice
        try office.run()
        defer {
            if office.isRunning { office.terminate() }
            office.waitUntilExit()
        }
        let pythonURL = libreOfficeURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/python")
        guard fileManager.isExecutableFile(atPath: pythonURL.path) else { throw ConversionError.documentEngineFailed(reason: "Runtime Python LibreOffice tidak ditemukan.") }
        Thread.sleep(forTimeInterval: 1.0)
        try runProcess(executable: pythonURL, arguments: [scriptURL.path, input.path, outputDirectory.path, baseName, "\(port)"], timeout: timeout, isCancelled: isCancelled)
    }

    private var spreadsheetExportScript: String {
        #"""
        import os, re, sys, time, uno
        from com.sun.star.beans import PropertyValue

        def prop(name, value):
            item = PropertyValue()
            item.Name = name
            item.Value = value
            return item

        input_path, output_dir, base_name, port = sys.argv[1:5]
        local_context = uno.getComponentContext()
        resolver = local_context.ServiceManager.createInstanceWithContext("com.sun.star.bridge.UnoUrlResolver", local_context)
        context = None
        for _ in range(30):
            try:
                context = resolver.resolve(f"uno:socket,host=127.0.0.1,port={port};urp;StarOffice.ComponentContext")
                break
            except Exception:
                time.sleep(0.25)
        if context is None:
            raise RuntimeError("LibreOffice UNO tidak siap")
        desktop = context.ServiceManager.createInstanceWithContext("com.sun.star.frame.Desktop", context)
        document = desktop.loadComponentFromURL(uno.systemPathToFileUrl(input_path), "_blank", 0, (prop("Hidden", True), prop("ReadOnly", True)))
        if document is None:
            raise RuntimeError("Spreadsheet tidak dapat dibuka")
        try:
            sheets = document.getSheets()
            count = sheets.getCount()
            safe_base = re.sub(r"[^A-Za-z0-9._-]+", "-", base_name).strip("-") or "Hasil"
            width = max(2, len(str(count)))
            for index in range(count):
                sheet = sheets.getByIndex(index)
                cursor = sheet.createCursor()
                cursor.gotoEndOfUsedArea(True)
                address = cursor.getRangeAddress()
                out_document = desktop.loadComponentFromURL("private:factory/scalc", "_blank", 0, (prop("Hidden", True),))
                if out_document is None:
                    raise RuntimeError("Spreadsheet sementara tidak dapat dibuat")
                try:
                    out_sheet = out_document.getSheets().getByIndex(0)
                    out_sheet.Name = "Data"
                    if address.EndColumn >= address.StartColumn and address.EndRow >= address.StartRow:
                        values = sheet.getCellRangeByPosition(address.StartColumn, address.StartRow, address.EndColumn, address.EndRow).getDataArray()
                        target = out_sheet.getCellRangeByPosition(0, 0, address.EndColumn - address.StartColumn, address.EndRow - address.StartRow)
                        target.setDataArray(values)
                    filename = f"{safe_base}-{index + 1:0{width}d}.csv"
                    output = os.path.join(output_dir, filename)
                    out_document.storeAsURL(uno.systemPathToFileUrl(output), (prop("FilterName", "Text - txt - csv (StarCalc)"), prop("FilterOptions", "44,34,76,1"), prop("Overwrite", True)))
                finally:
                    out_document.close(True)
        finally:
            document.close(True)
        """#
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
        case "txt": return "markdown"
        default: return source.fileExtension
        }
    }

    private func pandocOutputFormat(for target: TargetFormat) -> String {
        switch target {
        case .md: return "gfm"
        case .html: return "html"
        case .txt: return "markdown"
        default: return target.fileExtension
        }
    }

    private func runProcess(executable: URL, arguments: [String], timeout: TimeInterval, isCancelled: @escaping () -> Bool) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe

        // Drain stderr secara konkuren menggunakan readabilityHandler (B4).
        // Tanpa drain konkuren, pipe buffer (~64 KB) penuh → process block → deadlock.
        let errorQueue = DispatchQueue(label: "com.node.ceyloro.doc-converter-stderr")
        var errorBuffer = Data()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            errorQueue.sync {
                errorBuffer.append(data)
                if errorBuffer.count > 16384 { errorBuffer = errorBuffer.suffix(16384) }
            }
        }

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)

        // Pastikan readabilityHandler dibersihkan di semua jalur keluar (B4).
        defer { errorPipe.fileHandleForReading.readabilityHandler = nil }

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

        // Hentikan handler, lalu baca sisa data yang belum tertangkap.
        errorPipe.fileHandleForReading.readabilityHandler = nil
        let remaining = errorPipe.fileHandleForReading.readDataToEndOfFile()
        errorQueue.sync { errorBuffer.append(remaining) }

        let errorOutput = String(data: errorBuffer, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw ConversionError.documentEngineFailed(reason: errorOutput)
        }
    }
}
