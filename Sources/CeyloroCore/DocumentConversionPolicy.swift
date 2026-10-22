import Foundation

/// Matriks konversi dokumen untuk Fase A, PDF teks ke DOCX pada Fase B, dan ekspor spreadsheet/presentasi pada Fase C.
/// Kebijakan ini murni; ketersediaan LibreOffice/pandoc diperiksa oleh shell.
public struct DocumentConversionPolicy: Sendable {
    public init() {}

    public func targets(for source: FileFormat) -> [TargetFormat] {
        let extensionName = source.fileExtension
        switch extensionName {
        case "doc", "odt", "rtf":
            return [.pdf, .docx]
        case "docx":
            return [.pdf, .odt, .rtf, .md, .html, .txt]
        case "xls", "xlsx", "ods":
            return [.pdf, .csv]
        case "ppt", "pptx", "odp":
            return [.pdf, .png]
        case "md", "html", "txt":
            return [.docx, .pdf]
        case "pdf":
            return [.docx]
        default:
            return []
        }
    }

    public func isDocumentSource(_ source: FileFormat) -> Bool {
        targets(for: source).isEmpty == false
    }
}
