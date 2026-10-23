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
            result = try imageConverter.convert(input: input, target: target, temporaryDirectory: temporaryDirectory, progress: progress, isCancelled: isCancelled, options: ImageConversionOptions(jpgQuality: preset == .smaller ? 0.72 : 0.82, heicQuality: preset == .smaller ? 0.65 : 0.78))
        case .audio, .video:
            guard let target = TargetFormat(rawValue: plan.outputExtension) else { throw ConversionError.unsupportedConversion }
            result = try ffmpegConverter.convert(input: input, target: target, temporaryDirectory: temporaryDirectory, ffmpegURL: ffmpegURL, probe: probe, progress: progress, isCancelled: isCancelled, allowSameFormat: true, compression: preset)
        case .pdf:
            result = try compressPDF(input: input, temporaryDirectory: temporaryDirectory, progress: progress, isCancelled: isCancelled)
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

    private func compressPDF(input: URL, temporaryDirectory: URL, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws -> ConversionResult {
        guard let document = PDFDocument(url: input), !document.isLocked, document.pageCount > 0 else { throw ConversionError.invalidInput }
        // Gunakan subdirektori pages agar cleanup lebih bersih dan tidak mengganggu output.pdf
        let pagesDirectory = temporaryDirectory.appendingPathComponent("pages")
        try fileManager.createDirectory(at: pagesDirectory, withIntermediateDirectories: true)
        var pages: [URL] = []
        do {
            for index in 0..<document.pageCount {
                if isCancelled() { throw CancellationError() }
                guard let page = document.page(at: index), let image = render(page: page) else { throw ConversionError.encodingFailed }
                // Nama unik per halaman dengan zero-padding 4 digit agar urutan leksikografis konsisten
                let pageURL = pagesDirectory.appendingPathComponent(String(format: "page-%04d.jpg", index + 1))
                let options = ImageConversionOptions(jpgQuality: 0.78, heicQuality: 0.78)
                try write(image: image, to: pageURL, options: options)
                pages.append(pageURL)
                progress(0.5 * Double(index + 1) / Double(document.pageCount))
            }
            let output = temporaryDirectory.appendingPathComponent("output.pdf")
            try PDFBuilder.build(images: pages, outputURL: output, options: PDFMergeOptions(pageSize: .matchImage, margin: .none, quality: .balanced), progress: { value in
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
        let output = temporaryDirectory.appendingPathComponent("output.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", input.path, output.path]
        try process.run()
        while process.isRunning {
            if isCancelled() {
                process.terminate()
                process.waitUntilExit()
                try? fileManager.removeItem(at: output)
                throw CancellationError()
            }
            progress(0.5)
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard process.terminationStatus == 0, fileManager.fileExists(atPath: output.path) else {
            try? fileManager.removeItem(at: output)
            throw ConversionError.archiveConversionFailed
        }
        progress(1)
        return .files([output])
    }

    private func target(for extension: String) -> TargetFormat {
        TargetFormat(rawValue: `extension`) ?? .png
    }

    private func render(page: PDFPage) -> CGImage? {
        var box = page.bounds(for: .cropBox)
        if box.width <= 0 || box.height <= 0 { box = page.bounds(for: .mediaBox) }
        let scale = min(150.0 / 72.0, (120_000_000.0 / max(box.width * box.height, 1)).squareRoot())
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
