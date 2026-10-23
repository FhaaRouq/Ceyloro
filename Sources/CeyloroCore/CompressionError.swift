import Foundation

public enum CompressionError: LocalizedError, Equatable, Sendable {
    case alreadyOptimal(originalSize: Int64, generatedSize: Int64)

    public var errorDescription: String? {
        switch self {
        case .alreadyOptimal:
            return "File ini sudah dalam ukuran paling optimal dan tidak dapat diperkecil lagi tanpa merusak kualitas."
        }
    }
}
