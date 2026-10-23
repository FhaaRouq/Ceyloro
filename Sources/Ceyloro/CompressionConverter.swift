import Foundation
import PDFKit
import CoreGraphics
import ImageIO
import CeyloroCore

final class CompressionConverter {
    private let fileManager: FileManager
    private let imageConverter: ImageConverter
    private let ffmpegConverter: FFmpegConverter

    init(fileManager: FileManager = .default, imageConverter: ImageConverter = ImageConverter(), ffmpegConverter: FFmpegConverter = FFmpegConverter()) {
        self.fileManager = fileManager
        self.imageConverter = imageConverter
        self.ffmpegConverter = ffmpegConverter
    }

    func supports(files: [URL], ffmpegURL: URL?, probe: ProbeResult) -> Bool {
        guard let plan = CompressionPolicy.commonPlan(for: files.map(FileFormat.detect(url:))) else { return false }
        guard files.allSatisfy({ fileManager.isReadableFile(atPath: $0.path) }) else { return false }
        switch plan.kind {
        case .image:
            return imageConverter.supportedTargets(for: files, candidates: [target(for: plan.outputExtension)]).contains(target(for: plan.outputExtension))
        case .pdf:
            return files.allSatisfy { PDFDocument(url: $0)?.isLocked == false }
        case .audio, .video:
            guard let ffmpegURL else { return false }
            return fileManager.isExecutableFile(atPath: ffmpegURL.path) && files.allSatisfy {
                let format = FileFormat.detect(url: $0)
                guard let target = TargetFormat(rawValue: format.fileExtension) else { return false }
                return FFmpegConversionPolicy.supports(target: target, probe: probe)
            }
        case .document:
            return true
        }
    }

    func compress(input: URL, temporaryDirectory: URL, ffmpegURL: URL?, probe: ProbeResult, preset: CompressionPreset, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> ConversionResult {
        guard let plan = CompressionPolicy.plan(for: FileFormat.detect(url: input)) else { throw ConversionError.unsupportedConversion }
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let result: ConversionResult
        switch plan.kind {
        case .image:
            guard let target = TargetFormat(rawValue: plan.outputExtension) else { throw ConversionError.unsupportedConversion }
            let options = ImageConversionOptions(
                jpgQuality: preset == .smaller ? 0.72 : 0.82,
                heicQuality: preset == .smaller ? 0.65 : 0.78,
                quantizePNG: true
            )
            result = try imageConverter.convert(input: input, target: target, temporaryDirectory: temporaryDirectory, progress: progress, isCancelled: isCancelled, options: options)
        case .audio, .video:
            guard let target = TargetFormat(rawValue: plan.outputExtension) else { throw ConversionError.unsupportedConversion }
            result = try ffmpegConverter.convert(input: input, target: target, temporaryDirectory: temporaryDirectory, ffmpegURL: ffmpegURL, probe: probe, progress: progress, isCancelled: isCancelled, allowSameFormat: true, compression: preset)
        case .pdf:
            result = try compressPDF(input: input, temporaryDirectory: temporaryDirectory, preset: preset, progress: progress, isCancelled: isCancelled)
        case .document:
            result = try archiveDocument(input: input, temporaryDirectory: temporaryDirectory, progress: progress, isCancelled: isCancelled)
        }

        let inputSize = (try? fileManager.attributesOfItem(atPath: input.path)[.size] as? NSNumber)?.int64Value ?? 0
        let outputFiles: [URL]
        switch result {
        case let .files(files):
            outputFiles = files
        case let .collection(_, files):
            outputFiles = files
        }
        let outputSize = outputFiles.reduce(Int64(0)) { acc, fileURL in
            acc + ((try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0)
        }
        if inputSize > 0 && outputSize >= inputSize {
            for fileURL in outputFiles {
                try? fileManager.removeItem(at: fileURL)
            }
            throw CompressionError.alreadyOptimal(originalSize: inputSize, generatedSize: outputSize)
        }
        return result
    }

    private func compressPDF(input: URL, temporaryDirectory: URL, preset: CompressionPreset, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> ConversionResult {
        guard let document = PDFDocument(url: input), !document.isLocked, document.pageCount > 0 else { throw ConversionError.invalidInput }
        let output = temporaryDirectory.appendingPathComponent("output.pdf")

        // Inspeksi tipe PDF: Text/Vector vs Scanned/Photo (Temuan 1 & Bagian 4.2 PRD)
        var hasText = false
        for index in 0..<document.pageCount {
            if let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                hasText = true
                break
            }
        }

        if hasText {
            // Text/Vector PDF: DILARANG MERASTERISASI HALAMAN MENJADI BITMAP (AC-1).
            // Pertahankan struktur vektor & text layer dengan re-serialisasi Quartz stream optimization.
            progress(0.2)
            if isCancelled() { throw CancellationError() }
            let success = document.write(to: output)
            guard success && fileManager.fileExists(atPath: output.path) else {
                throw ConversionError.encodingFailed
            }
            progress(1.0)
            return .files([output])
        }

        // Scanned/Photo PDF: Dokumen didominasi raster bitmap. Lakukan downsampling & JPEG kompresi.
        // Gunakan subdirektori pages agar cleanup lebih bersih dan tidak mengganggu output.pdf
        let pagesDirectory = temporaryDirectory.appendingPathComponent("pages")
        try fileManager.createDirectory(at: pagesDirectory, withIntermediateDirectories: true)
        var pages: [URL] = []
        do {
            for index in 0..<document.pageCount {
                if isCancelled() { throw CancellationError() }
                // AC-7: Bungkus dengan autoreleasepool agar memori context grafis langsung dibebaskan per iterasi
                try autoreleasepool {
                    guard let page = document.page(at: index), let image = render(page: page, preset: preset) else {
                        throw ConversionError.encodingFailed
                    }
                    // Nama unik per halaman dengan zero-padding 4 digit agar urutan leksikografis konsisten
                    let pageURL = pagesDirectory.appendingPathComponent(String(format: "page-%04d.jpg", index + 1))
                    let quality = preset == .smaller ? 0.70 : 0.78
                    let options = ImageConversionOptions(jpgQuality: quality, heicQuality: quality)
                    try write(image: image, to: pageURL, options: options)
                    pages.append(pageURL)
                }
                progress(0.5 * Double(index + 1) / Double(document.pageCount))
            }
            let mergeQuality: PDFQuality = preset == .smaller ? .minimum : .balanced
            try PDFBuilder.build(images: pages, outputURL: output, options: PDFMergeOptions(pageSize: .matchImage, margin: .none, quality: mergeQuality), progress: { value in
                progress(0.5 + value * 0.5)
            }, isCancelled: isCancelled)
            // Bersihkan semua JPEG sementara setelah PDF selesai dibangun
            try? fileManager.removeItem(at: pagesDirectory)
            return .files([output])
        } catch {
            // Bersihkan sementara baik saat sukses maupun gagal
            try? fileManager.removeItem(at: pagesDirectory)
            throw error
        }
    }

    private func archiveDocument(input: URL, temporaryDirectory: URL, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> ConversionResult {
        let ext = input.pathExtension.lowercased()
        let finalExt = ext.isEmpty ? "docx" : ext
        let output = temporaryDirectory.appendingPathComponent("output.\(finalExt)")
        let extractedDir = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractedDir, withIntermediateDirectories: true)

        // 1. Ekstrak dokumen OpenXML (ZIP)
        let unpack = Process()
        unpack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unpack.arguments = ["-x", "-k", input.path, extractedDir.path]
        try unpack.run()
        unpack.waitUntilExit()

        guard unpack.terminationStatus == 0 else {
            // Jika bukan arsip zip (misal file plain text), salin ke output agar guard clause mengevaluasi
            try? fileManager.copyItem(at: input, to: output)
            return .files([output])
        }

        if isCancelled() { throw CancellationError() }
        progress(0.4)

        // 2. Kompresi berkas media di dalam word/media, xl/media, ppt/media
        let enumerator = fileManager.enumerator(at: extractedDir, includingPropertiesForKeys: [.isRegularFileKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            if isCancelled() { throw CancellationError() }
            let path = fileURL.path
            guard path.contains("/media/") else { continue }
            let fileExt = fileURL.pathExtension.lowercased()

            if fileExt == "jpg" || fileExt == "jpeg" {
                if let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                   let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    let tempURL = fileURL.appendingPathExtension("opt")
                    let options = ImageConversionOptions(jpgQuality: 0.75, heicQuality: 0.75)
                    if (try? write(image: image, to: tempURL, options: options)) != nil {
                        _ = try? fileManager.removeItem(at: fileURL)
                        _ = try? fileManager.moveItem(at: tempURL, to: fileURL)
                    }
                }
            } else if fileExt == "png" {
                if let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                   let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                   let quantized = PNGQuantizer.quantize(image: image) {
                    let tempURL = fileURL.appendingPathExtension("opt")
                    let pngType = UTType(filenameExtension: "png") ?? .png
                    if let dest = CGImageDestinationCreateWithURL(tempURL as CFURL, pngType.identifier as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, quantized, nil)
                        if CGImageDestinationFinalize(dest) {
                            _ = try? fileManager.removeItem(at: fileURL)
                            _ = try? fileManager.moveItem(at: tempURL, to: fileURL)
                        }
                    }
                }
            }
        }

        if isCancelled() { throw CancellationError() }
        progress(0.7)

        // 3. Kemas kembali dokumen dengan ekstensi asli menggunakan /usr/bin/zip
        let pack = Process()
        pack.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        pack.currentDirectoryURL = extractedDir
        pack.arguments = ["-q", "-r", "-9", output.path, "."]
        try pack.run()
        pack.waitUntilExit()

        guard pack.terminationStatus == 0 && fileManager.fileExists(atPath: output.path) else {
            // Fallback ke ditto jika zip gagal
            let dittoPack = Process()
            dittoPack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            dittoPack.currentDirectoryURL = extractedDir
            dittoPack.arguments = ["-c", "-k", ".", output.path]
            try dittoPack.run()
            dittoPack.waitUntilExit()
            guard dittoPack.terminationStatus == 0 && fileManager.fileExists(atPath: output.path) else {
                throw ConversionError.archiveConversionFailed
            }
        }

        try? fileManager.removeItem(at: extractedDir)
        progress(1.0)
        return .files([output])
    }

    private func target(for extension: String) -> TargetFormat {
        TargetFormat(rawValue: `extension`) ?? .png
    }

    private func render(page: PDFPage, preset: CompressionPreset = .balanced) -> CGImage? {
        var box = page.bounds(for: .cropBox)
        if box.width <= 0 || box.height <= 0 { box = page.bounds(for: .mediaBox) }
        let targetDPI: Double = preset == .smaller ? 120.0 : 150.0
        let scale = min(targetDPI / 72.0, (120_000_000.0 / max(box.width * box.height, 1)).squareRoot())
        let rotation = ((page.rotation % 360) + 360) % 360
        let rotated = rotation == 90 || rotation == 270
        let width = max(Int(((rotated ? box.height : box.width) * scale).rounded()), 1)
        let height = max(Int(((rotated ? box.width : box.height) * scale).rounded()), 1)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }

    private func write(image: CGImage, to url: URL, options: ImageConversionOptions) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { throw ConversionError.encodingFailed }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flattened = context.makeImage() else { throw ConversionError.encodingFailed }
        CGImageDestinationAddImage(destination, flattened, [kCGImageDestinationLossyCompressionQuality: options.jpgQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.encodingFailed }
    }
}
