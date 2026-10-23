import XCTest
import AppKit
import PDFKit
import CoreGraphics
@testable import Ceyloro
@testable import CeyloroCore

final class CompressionConverterTests: XCTestCase {
    func testImageCompressionWritesASeparateJPG() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroCompression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("photo.jpg")
        let image = NSImage(size: NSSize(width: 128, height: 128))
        image.lockFocus()
        for i in 0..<128 {
            NSColor(calibratedRed: CGFloat(i) / 128.0, green: 0.4, blue: 0.8, alpha: 1.0).setFill()
            NSRect(x: 0, y: CGFloat(i), width: 128, height: 1).fill()
        }
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        try XCTUnwrap(representation.representation(using: .jpeg, properties: [.compressionFactor: 1.0])).write(to: input)

        let result = try CompressionConverter().compress(input: input, temporaryDirectory: root.appendingPathComponent("temp"), ffmpegURL: nil, probe: .unknown, preset: .balanced, progress: { _ in }, isCancelled: { false })
        guard case let .files(outputs) = result, let output = outputs.first else {
            return XCTFail("Kompresi gambar tidak menghasilkan satu file")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(output.pathExtension, "jpg")
        XCTAssertNotEqual(try Data(contentsOf: input), try Data(contentsOf: output))
        let inputSize = (try FileManager.default.attributesOfItem(atPath: input.path)[.size] as? NSNumber)?.int64Value ?? 0
        let outputSize = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? 0
        XCTAssertLessThan(outputSize, inputSize, "Hasil kompresi harus lebih kecil dari ukuran asli")
    }

    // MARK: - Regression test A1: bug interpolasi nama halaman PDF macOS

    /// Verifikasi bahwa kompresi PDF multip halaman menghasilkan semua halaman unik.
    /// Sebelum fix, nama sementara "page-(index + 1).jpg" (tanpa backslash) membuat semua
    /// iterasi menulis ke file yang sama, sehingga semua halaman PDF output berisi gambar terakhir.
    func testPDFCompressionPreservesAllPagesWithDistinctContent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CeyloroCompressionPDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Buat PDF 3 halaman dengan warna berbeda: merah, hijau, biru
        let colors: [NSColor] = [.systemRed, .systemGreen, .systemBlue]
        let inputURL = root.appendingPathComponent("multipage.pdf")
        let inputPDF = PDFDocument()
        for color in colors {
            let pageImage = makeColorImage(color: color, size: NSSize(width: 200, height: 200))
            let pdfPage = try XCTUnwrap(makePDFPage(from: pageImage))
            inputPDF.insert(pdfPage, at: inputPDF.pageCount)
        }
        inputPDF.write(to: inputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inputURL.path), "Input PDF harus ada")

        // Jalankan kompresi
        let temp = root.appendingPathComponent("temp")
        let result = try CompressionConverter().compress(
            input: inputURL,
            temporaryDirectory: temp,
            ffmpegURL: nil,
            probe: .unknown,
            preset: .balanced,
            progress: { _ in },
            isCancelled: { false }
        )
        guard case let .files(outputs) = result, let outputURL = outputs.first else {
            return XCTFail("Kompresi PDF tidak menghasilkan file output")
        }
        XCTAssertEqual(outputURL.pathExtension, "pdf", "Output harus berupa PDF")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "File output harus ada")

        // Verifikasi jumlah halaman tetap 3
        let outputPDF = try XCTUnwrap(PDFDocument(url: outputURL), "Output harus bisa dibuka sebagai PDFDocument")
        XCTAssertEqual(outputPDF.pageCount, 3, "PDF output harus tetap memiliki 3 halaman")

        // Verifikasi setiap halaman memiliki konten yang berbeda (tidak semua duplikat halaman terakhir)
        // dengan cara membandingkan data render setiap halaman
        let pageDataSet = (0..<outputPDF.pageCount).compactMap { index -> Data? in
            guard let page = outputPDF.page(at: index) else { return nil }
            let bounds = page.bounds(for: .cropBox)
            let size = CGSize(width: max(bounds.width, 1), height: max(bounds.height, 1))
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(
                    data: nil, width: Int(size.width), height: Int(size.height),
                    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  ) else { return nil }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
            page.draw(with: .cropBox, to: ctx)
            guard let cgImage = ctx.makeImage() else { return nil }
            let mutableData = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, cgImage, nil)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return mutableData as Data
        }
        XCTAssertEqual(pageDataSet.count, 3, "Harus bisa merender semua 3 halaman")
        // Ketiga halaman harus memiliki data yang berbeda (tidak ada duplikat)
        let uniquePages = Set(pageDataSet.map { $0.hashValue })
        XCTAssertEqual(uniquePages.count, 3,
            "Ketiga halaman PDF output harus memiliki konten yang berbeda — " +
            "jika hanya 1 nilai unik, bug interpolasi nama halaman masih ada")

        // Verifikasi file sementara JPEG sudah dibersihkan
        let pagesDir = temp.appendingPathComponent("pages")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pagesDir.path),
            "Direktori halaman sementara harus dibersihkan setelah kompresi selesai")
    }

    // MARK: - Helpers untuk A1

    private func makeColorImage(color: NSColor, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.drawSwatch(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
    }

    private func makePDFPage(from nsImage: NSImage) -> PDFPage? {
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfpage-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        guard (try? pngData.write(to: tempURL)) != nil else { return nil }
        return PDFPage(image: NSImage(contentsOf: tempURL) ?? nsImage)
    }

    func testDocumentCompressionPackagesOriginalFileInZip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroCompression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("proposal.docx")
        try Data(repeating: 0x41, count: 50_000).write(to: input)

        let result = try CompressionConverter().compress(input: input, temporaryDirectory: root.appendingPathComponent("temp"), ffmpegURL: nil, probe: .unknown, preset: .balanced, progress: { _ in }, isCancelled: { false })
        guard case let .files(outputs) = result, let output = outputs.first else {
            return XCTFail("Kompresi dokumen tidak menghasilkan ZIP")
        }
        XCTAssertEqual(output.pathExtension, "zip")
        XCTAssertEqual(try Data(contentsOf: output).prefix(2), Data([0x50, 0x4B]))
    }

    // AC-2: Guard Clause Size Verification & Rollback
    func testCompressionNeverIncreasesFileSize() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroOptimal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Berkas kecil yang bila dikompresi ke format ZIP/JPEG malah bertambah besar akibat overhead header
        let input = root.appendingPathComponent("tiny.docx")
        try Data("short text".utf8).write(to: input)

        XCTAssertThrowsError(
            try CompressionConverter().compress(
                input: input,
                temporaryDirectory: root.appendingPathComponent("temp"),
                ffmpegURL: nil,
                probe: .unknown,
                preset: .balanced,
                progress: { _ in },
                isCancelled: { false }
            )
        ) { error in
            guard let compError = error as? CompressionError, case .alreadyOptimal = compError else {
                return XCTFail("Harus melempar CompressionError.alreadyOptimal, tetapi mendapat: \(error)")
            }
        }
    }
}
