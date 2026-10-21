import Foundation
import CoreGraphics

public struct PDFMergeOptions: Equatable, Codable, Sendable {
    public enum PageSize: String, Codable, CaseIterable, Sendable {
        case a4
        case letter
        case matchImage
    }

    public enum Margin: String, Codable, CaseIterable, Sendable {
        case none
        case medium

        public var points: CGFloat {
            switch self {
            case .none: return 0
            case .medium: return 36
            }
        }
    }

    public enum Quality: String, Codable, CaseIterable, Sendable {
        case original
        case balanced
    }

    public var pageSize: PageSize
    public var margin: Margin
    public var quality: Quality

    public init(pageSize: PageSize = .a4, margin: Margin = .none, quality: Quality = .balanced) {
        self.pageSize = pageSize
        self.margin = margin
        self.quality = quality
    }
}

public enum PDFMergeMode: String, Codable, Sendable {
    case single
    case each
}

public enum ImageSortMode: Sendable {
    case nameAscending
    case nameDescending
    case createdAscending
    case modifiedAscending
}

public enum ImageSorting {
    public static func sorted(_ urls: [URL], by mode: ImageSortMode) -> [URL] {
        urls.sorted { lhs, rhs in
            switch mode {
            case .nameAscending:
                return compareNames(lhs, rhs) == .orderedAscending
            case .nameDescending:
                return compareNames(lhs, rhs) == .orderedDescending
            case .createdAscending:
                return compareDates(lhs, rhs, key: .creationDateKey)
            case .modifiedAscending:
                return compareDates(lhs, rhs, key: .contentModificationDateKey)
            }
        }
    }

    private static func compareNames(_ lhs: URL, _ rhs: URL) -> ComparisonResult {
        let result = lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent)
        if result == .orderedSame {
            return lhs.path.localizedCompare(rhs.path)
        }
        return result
    }

    private static func compareDates(_ lhs: URL, _ rhs: URL, key: URLResourceKey) -> Bool {
        let leftDate = (try? lhs.resourceValues(forKeys: [key]).allValues[key]) as? Date
        let rightDate = (try? rhs.resourceValues(forKeys: [key]).allValues[key]) as? Date
        switch (leftDate, rightDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, .some):
            return true
        case (.some, nil):
            return false
        default:
            return compareNames(lhs, rhs) == .orderedAscending
        }
    }
}

public struct MergeListModel: Equatable, Sendable {
    public private(set) var items: [URL]

    public init(items: [URL]) {
        self.items = items
    }

    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moving = offsets.sorted().map { items[$0] }
        for index in offsets.sorted(by: >) {
            items.remove(at: index)
        }
        let removedBeforeDestination = offsets.filter { $0 < destination }.count
        let adjustedDestination = max(0, min(items.count, destination - removedBeforeDestination))
        items.insert(contentsOf: moving, at: adjustedDestination)
    }

    public mutating func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            items.remove(at: index)
        }
    }

    public mutating func sort(by mode: ImageSortMode) {
        items = ImageSorting.sorted(items, by: mode)
    }

    public mutating func reverse() {
        items.reverse()
    }
}

public enum PageLayout {
    public static func pageSize(forImage imageSize: CGSize, option: PDFMergeOptions.PageSize) -> CGSize {
        switch option {
        case .a4:
            return orientedPage(width: 595.28, height: 841.89, imageSize: imageSize)
        case .letter:
            return orientedPage(width: 612, height: 792, imageSize: imageSize)
        case .matchImage:
            let width = max(imageSize.width, 1)
            let height = max(imageSize.height, 1)
            let scale = min(842 / max(width, height), 1)
            return CGSize(width: width * scale, height: height * scale)
        }
    }

    public static func imageRect(imageSize: CGSize, pageSize: CGSize, margin: PDFMergeOptions.Margin) -> CGRect {
        let inset = margin.points
        let available = CGRect(x: inset, y: inset, width: max(pageSize.width - inset * 2, 1), height: max(pageSize.height - inset * 2, 1))
        let width = max(imageSize.width, 1)
        let height = max(imageSize.height, 1)
        let scale = min(available.width / width, available.height / height)
        let size = CGSize(width: width * scale, height: height * scale)
        return CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2, width: size.width, height: size.height)
    }

    private static func orientedPage(width: CGFloat, height: CGFloat, imageSize: CGSize) -> CGSize {
        let imageIsLandscape = imageSize.width > imageSize.height
        let pageIsLandscape = width > height
        return imageIsLandscape == pageIsLandscape ? CGSize(width: width, height: height) : CGSize(width: height, height: width)
    }
}
