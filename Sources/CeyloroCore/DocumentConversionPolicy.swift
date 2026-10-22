import Foundation

/// Matriks konversi dokumen untuk Fase A.
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
        case "xls", "xlsx", "ods", "ppt", "pptx", "odp":
            return [.pdf]
        case "md", "html", "txt":
            return [.docx, .pdf]
        default:
            return []
        }
    }

    public func isDocumentSource(_ source: FileFormat) -> Bool {
        targets(for: source).isEmpty == false
    }
}
