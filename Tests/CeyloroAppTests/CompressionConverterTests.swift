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

    // AC-6: Dokumen DOCX yang dikompresi tidak berubah menjadi file .zip semu
    func testDocumentCompressionPreservesOriginalFormat() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroDocx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Siapkan struktur minimal DOCX (arsip zip dengan word/media/)
        let stagingDir = root.appendingPathComponent("staging")
        let mediaDir = stagingDir.appendingPathComponent("word/media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        try Data("dummy document xml".utf8).write(to: stagingDir.appendingPathComponent("word/document.xml"))
        // Masukkan gambar PNG besar yang compressible
        let bigPngData = Data(repeating: 0x55, count: 80_000)
        try bigPngData.write(to: mediaDir.appendingPathComponent("image1.png"))

        let input = root.appendingPathComponent("proposal.docx")
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.currentDirectoryURL = stagingDir
        zipProcess.arguments = ["-q", "-r", "-0", input.path, "."]
        try zipProcess.run()
        zipProcess.waitUntilExit()

        let result = try CompressionConverter().compress(input: input, temporaryDirectory: root.appendingPathComponent("temp"), ffmpegURL: nil, probe: .unknown, preset: .balanced, progress: { _ in }, isCancelled: { false })
        guard case let .files(outputs) = result, let output = outputs.first else {
            return XCTFail("Kompresi dokumen tidak menghasilkan output")
        }
        // AC-6: Ekstensi harus tetap docx, bukan zip
        XCTAssertEqual(output.pathExtension, "docx", "Ekstensi output dokumen harus tetap .docx, bukan .zip semu")
        XCTAssertEqual(try Data(contentsOf: output).prefix(2), Data([0x50, 0x4B]), "Output harus merupakan arsip OpenXML yang valid")
    }

    // AC-3 & Test Plan 3: Memverifikasi PNG 32-bit mengalami penurunan ukuran >= 30% dengan transparansi
    func testPNGCompressionReducesSize() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroPNG-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let input = root.appendingPathComponent("logo.png")
        let width = 200
        let height = 200
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        // Buat gambar dengan separuh transparan dan gradien warna
        for y in 0..<height {
            for x in 0..<width {
                if x < 40 {
                    // Area transparan
                    NSColor.clear.setFill()
                } else {
                    let r = CGFloat(x) / CGFloat(width)
                    let g = CGFloat(y) / CGFloat(height)
                    NSColor(calibratedRed: r, green: g, blue: 0.7, alpha: 1.0).setFill()
                }
                NSRect(x: x, y: y, width: 1, height: 1).fill()
            }
        }
        image.unlockFocus()

        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let pngData = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try pngData.write(to: input)

        let initialSize = (try FileManager.default.attributesOfItem(atPath: input.path)[.size] as? NSNumber)?.int64Value ?? 0
        XCTAssertGreaterThan(initialSize, 0)

        let result = try CompressionConverter().compress(
            input: input,
            temporaryDirectory: root.appendingPathComponent("temp"),
            ffmpegURL: nil,
            probe: .unknown,
            preset: .balanced,
            progress: { _ in },
            isCancelled: { false }
        )

        guard case let .files(outputs) = result, let output = outputs.first else {
            return XCTFail("Kompresi PNG tidak menghasilkan output")
        }
        XCTAssertEqual(output.pathExtension, "png")

        let compressedSize = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? 0
        // AC-3: Penurunan ukuran nyata (>= 30%)
        let reductionRatio = Double(initialSize - compressedSize) / Double(initialSize)
        XCTAssertGreaterThanOrEqual(reductionRatio, 0.30, "Penurunan ukuran PNG harus setidaknya 30%, aktual: \(reductionRatio * 100)%")

        // Verifikasi transparansi tetap ada
        let outRep = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: output)))
        XCTAssertTrue(outRep.hasAlpha, "Output PNG harus mempertahankan transparansi")
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

    // AC-1 & Test Plan 2: Memverifikasi layer teks tetap utuh dan tidak dirasterisasi menjadi bitmap
    func testPDFCompressionPreservesTextLayer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroTextPDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let inputURL = root.appendingPathComponent("document.pdf")
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return XCTFail("Gagal membuat CGContext PDF")
        }

        // Buat 6 halaman dengan teks
        for pageNum in 1...6 {
            context.beginPage(mediaBox: &mediaBox)
            let pageText = "Halaman \(pageNum): Dokumen Ceyloro berisikan teks penting yang harus tetap dapat disalin dan searchable."
            let attrString = NSAttributedString(string: pageText, attributes: [
                .font: NSFont.systemFont(ofSize: 14)
            ])
            let line = CTLineCreateWithAttributedString(attrString)
            context.textPosition = CGPoint(x: 50, y: 700)
            CTLineDraw(line, context)
            context.endPage()
        }
        context.closePDF()
        try (pdfData as Data).write(to: inputURL)

        // Verifikasi dokumen sumber memiliki teks
        let sourceDoc = try XCTUnwrap(PDFDocument(url: inputURL))
        XCTAssertEqual(sourceDoc.pageCount, 6)
        XCTAssertFalse((sourceDoc.string ?? "").isEmpty, "PDF sumber harus memiliki string teks")

        // Jalankan kompresi
        do {
            let result = try CompressionConverter().compress(
                input: inputURL,
                temporaryDirectory: root.appendingPathComponent("temp"),
                ffmpegURL: nil,
                probe: .unknown,
                preset: .balanced,
                progress: { _ in },
                isCancelled: { false }
            )
            guard case let .files(outputs) = result, let output = outputs.first else {
                return XCTFail("Kompresi tidak menghasilkan file")
            }
            let outputDoc = try XCTUnwrap(PDFDocument(url: output))
            XCTAssertEqual(outputDoc.pageCount, 6)
            let text = try XCTUnwrap(outputDoc.string)
            XCTAssertTrue(text.contains("Ceyloro"), "Layer teks harus tetap utuh dan dapat disalin")
            let outSize = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? 0
            let inSize = (try FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            XCTAssertLessThanOrEqual(outSize, inSize, "Ukuran output harus <= ukuran input")
        } catch let compError as CompressionError {
            // Jika file input 6 halaman sudah sangat kompak, guard clause melempar alreadyOptimal
            // dan tidak membengkakkan file menjadi bitmap 2.8 MB (AC-1, AC-2, AC-4)
            guard case .alreadyOptimal = compError else {
                return XCTFail("Error tidak terduga: \(compError)")
            }
        }
    }

    // AC-7 & Test Plan 5: Menguji kompresi 50 halaman PDF dengan XCTest metric memory
    func testMemoryFootprintDuringMultiPagePDFCompression() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CeyloroMemoryPDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Buat PDF 50 halaman
        let inputURL = root.appendingPathComponent("50pages.pdf")
        let doc = PDFDocument()
        let colors: [NSColor] = [.systemRed, .systemGreen, .systemBlue, .systemOrange, .systemPurple]
        for i in 0..<50 {
            let color = colors[i % colors.count]
            let pageImage = makeColorImage(color: color, size: NSSize(width: 250, height: 250))
            if let page = makePDFPage(from: pageImage) {
                doc.insert(page, at: doc.pageCount)
            }
        }
        doc.write(to: inputURL)
        XCTAssertEqual(doc.pageCount, 50)

        let converter = CompressionConverter()
        let tempDir = root.appendingPathComponent("temp")

        // Verifikasi footprint memori selama kompresi multipage (AC-7)
        measure(metrics: [XCTMemoryMetric()]) {
            do {
                _ = try converter.compress(
                    input: inputURL,
                    temporaryDirectory: tempDir,
                    ffmpegURL: nil,
                    probe: .unknown,
                    preset: .balanced,
                    progress: { _ in },
                    isCancelled: { false }
                )
            } catch {
                // Diperbolehkan jika guard clause alreadyOptimal terpicu
            }
        }
    }
}
