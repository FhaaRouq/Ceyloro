import XCTest
import CoreText
import CoreGraphics
@testable import Ceyloro

final class DocumentConverterTests: XCTestCase {
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
