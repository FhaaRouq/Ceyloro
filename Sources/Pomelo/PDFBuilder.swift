import CoreGraphics
import Foundation
import ImageIO
import PomeloCore
import UniformTypeIdentifiers

enum PDFBuilder {
    static func build(images: [URL], outputURL: URL, options: PDFMergeOptions, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws {
        guard !images.isEmpty else { throw ConversionError.invalidInput }
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ConversionError.encodingFailed
        }
        var finishedPages = 0
        do {
            for input in images {
                if isCancelled() { throw CancellationError() }
                try autoreleasepool {
                    guard let image = image(at: input, quality: options.quality) else { throw ConversionError.invalidInput }
                    let pageSize = PageLayout.pageSize(forImage: CGSize(width: image.width, height: image.height), option: options.pageSize)
                    let imageRect = PageLayout.imageRect(imageSize: CGSize(width: image.width, height: image.height), pageSize: pageSize, margin: options.margin)
                    let pageBox = CGRect(origin: .zero, size: pageSize)
                    var pageBoxValue = pageBox
                    let pageBoxData = Data(bytes: &pageBoxValue, count: MemoryLayout<CGRect>.size)
                    context.beginPDFPage([kCGPDFContextMediaBox: pageBoxData] as CFDictionary)
                    context.setFillColor(CGColor(gray: 1, alpha: 1))
                    context.fill(pageBox)
                    context.draw(image, in: imageRect)
                    context.endPDFPage()
                    finishedPages += 1
                    progress(Double(finishedPages) / Double(images.count))
                }
            }
            context.closePDF()
        } catch {
            context.closePDF()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func image(at url: URL, quality: PDFMergeOptions.Quality) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary? else { return nil }
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let limit = quality == .balanced ? min(max(width, height), 2480) : max(width, height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        guard quality == .balanced else { return thumbnail }
        return jpegReencoded(thumbnail, quality: 0.85) ?? thumbnail
    }

    private static func jpegReencoded(_ image: CGImage, quality: Double) -> CGImage? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
