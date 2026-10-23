import XCTest
import CoreText
import CoreGraphics
@testable import Ceyloro
@testable import CeyloroCore

final class DocumentConverterTests: XCTestCase {
    // MARK: - Regression test A5: supportedTargets harus mengizinkan PDF sebagai input

    /// Sebelum fix, guard `kind == .document` memblokir PDF sehingga DOCX tidak pernah
    /// muncul sebagai target meski policy dan convert() mendukungnya.
    func testSupportedTargetsReturnsDOCXForTextPDFWhenPandocAvailable() throws {
        let pandocURL = URL(fileURLWithPath: "/usr/local/bin/pandoc")
        guard FileManager.default.isExecutableFile(atPath: pandocURL.path) else {
            throw XCTSkip("Pandoc tidak terpasang pada mesin test ini.")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CeyloroA5-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pdfURL = root.appendingPathComponent("text.pdf")
        try makeTextPDF(at: pdfURL)

        let targets = DocumentConverter().supportedTargets(
            for: [pdfURL],
            candidates: [.docx, .pdf, .txt],
            libreOfficeURL: nil,
            pandocURL: pandocURL
        )
        XCTAssertTrue(targets.contains(.docx),
            "DOCX harus muncul sebagai target untuk PDF berteks saat Pandoc tersedia — " +
            "jika kosong, guard kind == .document masih memblokir PDF")
    }

    // MARK: - Regression test A5: pengecekan batch harus per-file, bukan files[0]

    /// Sebelum fix, `hasExtractableText(at: files[0])` dipakai sebagai proxy untuk semua
    /// file dalam batch. Batch [scan, teks] seharusnya tidak menawarkan DOCX karena file
    /// pertama (scan) tidak punya teks.
    func testBatchWithScanPDFFirstBlocksDOCXTarget() throws {
        let pandocURL = URL(fileURLWithPath: "/usr/local/bin/pandoc")
        guard FileManager.default.isExecutableFile(atPath: pandocURL.path) else {
            throw XCTSkip("Pandoc tidak terpasang pada mesin test ini.")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CeyloroA5Batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let textPDF = root.appendingPathComponent("text.pdf")
        let scanPDF = root.appendingPathComponent("scan.pdf")
        try makeTextPDF(at: textPDF)
        try makeImageOnlyPDF(at: scanPDF)    // PDF tanpa teks yang bisa diekstrak

        let converter = DocumentConverter()

        // [teks, scan] → DOCX tidak bisa ditawarkan karena scan tidak punya teks
        let targetsTextFirst = converter.supportedTargets(
            for: [textPDF, scanPDF],
            candidates: [.docx],
            libreOfficeURL: nil,
            pandocURL: pandocURL
        )
        XCTAssertFalse(targetsTextFirst.contains(.docx),
            "Batch [teks, scan] tidak boleh menawarkan DOCX karena file scan tidak punya teks")

        // [scan, teks] → sama, urutan tidak boleh memengaruhi hasil
        let targetsScanFirst = converter.supportedTargets(
            for: [scanPDF, textPDF],
            candidates: [.docx],
            libreOfficeURL: nil,
            pandocURL: pandocURL
        )
        XCTAssertFalse(targetsScanFirst.contains(.docx),
            "Batch [scan, teks] tidak boleh menawarkan DOCX — " +
            "sebelum fix, bug files[0] membuat urutan menentukan hasil")

        // [teks saja] → DOCX harus tersedia
        let targetsSingle = converter.supportedTargets(
            for: [textPDF],
            candidates: [.docx],
            libreOfficeURL: nil,
            pandocURL: pandocURL
        )
        XCTAssertTrue(targetsSingle.contains(.docx),
            "PDF berteks tunggal harus tetap menawarkan DOCX")
    }

    // MARK: - Helpers

    private func makeImageOnlyPDF(at url: URL) throws {
        // Buat PDF dengan satu halaman gambar solid — tidak ada teks yang bisa diekstrak
        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "CeyloroTests", code: 2)
        }
        context.beginPDFPage(nil)
        context.setFillColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.endPDFPage()
        context.closePDF()
    }

    func testTextPDFConvertsToDOCXWithPandoc() throws {
        let pandocURL = URL(fileURLWithPath: "/usr/local/bin/pandoc")
        guard FileManager.default.isExecutableFile(atPath: pandocURL.path) else {
            throw XCTSkip("Pandoc tidak terpasang pada mesin test ini.")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroDocument-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let input = root.appendingPathComponent("input.pdf")
        try makeTextPDF(at: input)
        let temporary = root.appendingPathComponent("job", isDirectory: true)
        let output = try DocumentConverter().convert(
            input: input,
            target: .docx,
            temporaryDirectory: temporary,
            libreOfficeURL: nil,
            pandocURL: pandocURL,
            progress: { _ in },
            isCancelled: { false }
        )

        guard case let .files(files) = output, let docx = files.first else {
            return XCTFail("Konversi PDF teks tidak mengembalikan DOCX.")
        }
        XCTAssertEqual(docx.pathExtension, "docx")
        XCTAssertGreaterThan(try Data(contentsOf: docx).count, 0)
    }

    // MARK: - Regression test B4: drain stderr konkuren — 10 MB ke stderr tidak boleh hang

    func testRunProcessHandlesLargeStderrWithoutHang() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CeyloroB4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Buat fake pandoc yang menulis 10 MB ke stderr lalu exit 0
        let fakePandoc = root.appendingPathComponent("fake-pandoc")
        let script = """
        #!/bin/sh
        # Tulis 10 MB ke stderr untuk menguji drain konkuren (B4)
        dd if=/dev/zero bs=1048576 count=10 2>/dev/null >&2
        # Cari argumen --output dan tulis file output
        output=""
        prev=""
        for arg in "$@"; do
            if [ "$prev" = "--output" ]; then output="$arg"; fi
            prev="$arg"
        done
        [ -n "$output" ] && echo "fake docx content" > "$output"
        exit 0
        """
        try script.write(to: fakePandoc, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakePandoc.path)

        // Buat PDF dengan teks yang dapat diekstrak
        let input = root.appendingPathComponent("input.pdf")
        try makeTextPDF(at: input)

        // Konversi PDF → DOCX dengan fake pandoc.
        // Sebelum fix B4, process block saat stderr pipe buffer penuh → hang.
        let tempDir = root.appendingPathComponent("temp", isDirectory: true)
        let result = try DocumentConverter().convert(
            input: input,
            target: .docx,
            temporaryDirectory: tempDir,
            libreOfficeURL: nil,
            pandocURL: fakePandoc,
            progress: { _ in },
            isCancelled: { false }
        )

        guard case let .files(files) = result, let output = files.first else {
            return XCTFail("Konversi dengan fake pandoc yang menulis 10 MB stderr tidak menghasilkan output.")
        }
        XCTAssertEqual(output.pathExtension, "docx")
    }

    private func makeTextPDF(at url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "CeyloroTests", code: 1)
        }
        context.beginPDFPage(nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        ]
        let attributed = NSAttributedString(string: "Ceyloro PDF DOCX test", attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
    }
}
