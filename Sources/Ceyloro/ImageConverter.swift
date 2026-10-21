import AppKit
import CoreGraphics
import ImageIO
import PDFKit
import CeyloroCore
import UniformTypeIdentifiers

struct ImageConversionOptions: Sendable {
    var jpgQuality: Double
    var heicQuality: Double
    var pdf: PDFMergeOptions

    static let standard = ImageConversionOptions(jpgQuality: 0.92, heicQuality: 0.92, pdf: PDFMergeOptions())

    init(jpgQuality: Double = 0.92, heicQuality: Double = 0.92, pdf: PDFMergeOptions = PDFMergeOptions()) {
        self.jpgQuality = min(max(jpgQuality, 0), 1)
        self.heicQuality = min(max(heicQuality, 0), 1)
        self.pdf = pdf
    }
}

final class ImageConverter {
    func supportedTargets(for files: [URL], candidates: [TargetFormat]) -> [TargetFormat] {
        candidates.filter { target in
            guard !files.isEmpty else { return false }
            return files.allSatisfy { file in
                let format = FileFormat.detect(url: file)
                switch format.kind {
                case .image:
                    guard canReadImage(at: file) else { return false }
                    return target == .pdf || canWriteImage(target)
                case .pdf:
                    guard let document = PDFDocument(url: file), !document.isLocked else { return false }
                    return target == .txt || canWriteImage(target)
                default:
                    return false
                }
            }
        }
    }

    func convert(input: URL, target: TargetFormat, temporaryDirectory: URL, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool, options: ImageConversionOptions = .standard) throws -> ConversionResult {
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let source = FileFormat.detect(url: input)
        switch (source.kind, target) {
        case (.image, .pdf):
            progress(0.1)
            let output = temporaryDirectory.appendingPathComponent("output.pdf")
            try PDFBuilder.build(images: [input], outputURL: output, options: options.pdf, progress: progress, isCancelled: isCancelled)
            return .files([output])

        case (.pdf, .txt):
            progress(0.4)
            guard let document = PDFDocument(url: input), !document.isLocked else { throw ConversionError.invalidInput }
            guard let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConversionError.noText
            }
            let output = temporaryDirectory.appendingPathComponent("output.txt")
            try text.write(to: output, atomically: true, encoding: .utf8)
            progress(1)
            return .files([output])

        case (.pdf, .jpg), (.pdf, .png):
            guard let document = PDFDocument(url: input), !document.isLocked, document.pageCount > 0 else { throw ConversionError.invalidInput }
            var outputs: [URL] = []
            let pageCount = document.pageCount
            let width = max(String(pageCount).count, 2)
            for index in 0..<pageCount {
                if isCancelled() { throw CancellationError() }
                var rendered: CGImage?
                autoreleasepool {
                    rendered = document.page(at: index).flatMap(render(page:))
                }
                guard let image = rendered else { throw ConversionError.encodingFailed }
                let suffix = String(format: "%0*d", width, index + 1)
                let output = temporaryDirectory.appendingPathComponent("page-\(suffix).\(target.fileExtension)")
                try write(image: image, to: output, target: target, options: options)
                outputs.append(output)
                progress(Double(index + 1) / Double(pageCount))
            }
            return pageResult(input: input, outputs: outputs)

        case (.image, .jpg), (.image, .png), (.image, .heic), (.image, .tiff):
            guard let sourceImage = CGImageSourceCreateWithURL(input as CFURL, nil), canReadImage(at: input), canWriteImage(target) else {
                throw ConversionError.invalidInput
            }
            let sourceCount = FileFormat.detect(url: input).fileExtension == "tiff" ? CGImageSourceGetCount(sourceImage) : 1
            let frameCount = max(sourceCount, 1)
            var outputs: [URL] = []
            for index in 0..<frameCount {
                if isCancelled() { throw CancellationError() }
                guard let image = orientedImage(from: sourceImage, index: index) else { throw ConversionError.encodingFailed }
                let filename: String
                if frameCount == 1 {
                    filename = "output.\(target.fileExtension)"
                } else {
                    filename = "page-\(String(format: "%0*d", max(String(frameCount).count, 2), index + 1)).\(target.fileExtension)"
                }
                let output = temporaryDirectory.appendingPathComponent(filename)
                let properties = normalizedProperties(from: sourceImage, index: index)
                try write(image: image, to: output, target: target, options: options, metadata: properties)
                outputs.append(output)
                progress(Double(index + 1) / Double(frameCount))
            }
            return frameCount > 1 ? .collection(name: input.deletingPathExtension().lastPathComponent, files: outputs) : .files(outputs)

        default:
            throw ConversionError.unsupportedConversion
        }
    }

    private func pageResult(input: URL, outputs: [URL]) -> ConversionResult {
        guard outputs.count > 1 else { return .files(outputs) }
        return .collection(name: input.deletingPathExtension().lastPathComponent, files: outputs)
    }

    private func render(page: PDFPage) -> CGImage? {
        var box = page.bounds(for: .cropBox)
        if box.width <= 0 || box.height <= 0 {
            box = page.bounds(for: .mediaBox)
        }
        guard box.width > 0, box.height > 0 else { return nil }
        let maxPixels = 120_000_000.0
        let area = max(box.width * box.height, 1)
        let scale = min(300.0 / 72.0, (maxPixels / area).squareRoot())
        let rotation = ((page.rotation % 360) + 360) % 360
        let rotated = rotation == 90 || rotation == 270
        let width = max(Int(((rotated ? box.height : box.width) * scale).rounded()), 1)
        let height = max(Int(((rotated ? box.width : box.height) * scale).rounded()), 1)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        switch rotation {
        case 90:
            context.translateBy(x: CGFloat(width), y: 0)
            context.rotate(by: .pi / 2)
        case 180:
            context.translateBy(x: CGFloat(width), y: CGFloat(height))
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: 0, y: CGFloat(height))
            context.rotate(by: -.pi / 2)
        default:
            break
        }
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
        return context.makeImage()
    }

    private func canReadImage(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(source) else { return false }
        let identifiers = (CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []
        return identifiers.contains(sourceType as String)
    }

    private func canWriteImage(_ target: TargetFormat) -> Bool {
        guard let type = imageType(for: target) else { return false }
        let identifiers = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return identifiers.contains(type.identifier)
    }

    private func imageType(for target: TargetFormat) -> UTType? {
        switch target {
        case .jpg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .tiff: return .tiff
        default: return nil
        }
    }

    private func orientedImage(from source: CGImageSource, index: Int) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary?,
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    private func normalizedProperties(from source: CGImageSource, index: Int) -> [CFString: Any] {
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]) ?? [:]
        properties[kCGImagePropertyOrientation] = 1
        return properties
    }

    private func write(image: CGImage, to url: URL, target: TargetFormat, options: ImageConversionOptions, metadata: [CFString: Any] = [:]) throws {
        guard let type = imageType(for: target), let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { throw ConversionError.encodingFailed }
        var properties = metadata
        switch target {
        case .jpg:
            guard let flattened = flattenForJPEG(image) else { throw ConversionError.encodingFailed }
            CGImageDestinationAddImage(destination, flattened, [kCGImageDestinationLossyCompressionQuality: options.jpgQuality] as CFDictionary)
        case .heic:
            properties[kCGImageDestinationLossyCompressionQuality] = options.heicQuality
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        default:
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.encodingFailed }
    }

    private func flattenForJPEG(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

enum ConversionError: LocalizedError {
    case invalidInput
    case noText
    case encodingFailed
    case audioEngineUnavailable
    case videoEngineUnavailable
    case archiveEngineUnavailable
    case archiveConversionFailed
    case ffmpegUnavailable
    case ffmpegFailed
    case unsupportedConversion

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "File tidak valid, terkunci, atau tidak dapat dibaca."
        case .noText: return "PDF tidak berisi teks, mungkin hasil scan."
        case .encodingFailed: return "Ceyloro tidak dapat menulis hasil konversi."
        case .audioEngineUnavailable: return "Mesin audio macOS tidak mendukung format ini."
        case .videoEngineUnavailable: return "Mesin video macOS tidak mendukung format ini."
        case .archiveEngineUnavailable: return "Mesin arsip macOS tidak tersedia untuk format ini."
        case .archiveConversionFailed: return "Ceyloro tidak dapat membuat arsip hasil."
        case .ffmpegUnavailable: return "FFmpeg belum tersedia untuk format ini."
        case .ffmpegFailed: return "FFmpeg gagal memproses file ini."
        case .unsupportedConversion: return "Format ini belum didukung di MVP."
        }
    }
}
