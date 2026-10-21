import AppKit
import Darwin
import PomeloCore

enum WheelMode: String {
    case convert
    case tools
    case actions
}

enum WheelAction {
    case copy
    case copyPath
    case terminal
    case airDrop
    case move
    case float
}

struct WheelItem {
    let title: String
    let target: TargetFormat?
    let action: WheelAction?
    let symbolName: String

    init(title: String, target: TargetFormat?, action: WheelAction?, symbolName: String? = nil) {
        self.title = title
        self.target = target
        self.action = action
        self.symbolName = symbolName ?? Self.symbolName(target: target, action: action)
    }

    private static func symbolName(target: TargetFormat?, action: WheelAction?) -> String {
        if let target {
            switch target {
            case .jpg, .png, .heic, .tiff: return "photo"
            case .pdf: return "doc.richtext"
            case .txt: return "doc.text"
            }
        }
        switch action {
        case .copy: return "doc.on.doc"
        case .copyPath: return "link"
        case .terminal: return "terminal"
        case .airDrop: return "paperplane"
        case .move: return "arrow.right"
        case .float: return "pin"
        case .none: return "circle"
        }
    }
}

protocol RadialOverlayDelegate: AnyObject {
    func radialOverlay(_ overlay: RadialOverlay, didDrop files: [URL], item: WheelItem, mode: WheelMode)
    func radialOverlayDidCancel(_ overlay: RadialOverlay)
}

final class RadialOverlay: NSPanel {
    weak var overlayDelegate: RadialOverlayDelegate?
    private let wheelView: RadialOverlayView
    private(set) var items: [WheelItem] = []
    private(set) var mode: WheelMode = .convert
    private var files: [URL] = []
    private let geometry = RadialGeometry()
    private var dismissTimer: Timer?

    override var canBecomeKey: Bool { true }

    init() {
        let size = NSSize(width: 1, height: 1)
        wheelView = RadialOverlayView(frame: NSRect(origin: .zero, size: size))
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        contentView = wheelView
        wheelView.delegate = self
        registerForDraggedTypes([.fileURL, .URL])
    }

    func present(files: [URL], mode: WheelMode, items: [WheelItem], at point: NSPoint) {
        self.files = files
        self.mode = mode
        self.items = items
        wheelView.items = items
        wheelView.mode = mode
        wheelView.selectionSummary = Self.summary(for: files)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let selectedScreenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = screen?.visibleFrame ?? selectedScreenFrame
        let screenFrame = NSScreen.screens.dropFirst().reduce(selectedScreenFrame) { $0.union($1.frame) }
        setFrame(screenFrame, display: true)
        wheelView.frame = contentView?.bounds ?? NSRect(origin: .zero, size: screenFrame.size)
        let margin = geometry.discRadius + 21
        let clampedX = min(max(point.x, visibleFrame.minX + margin), visibleFrame.maxX - margin)
        let clampedY = min(max(point.y, visibleFrame.minY + margin), visibleFrame.maxY - margin)
        wheelView.centerPoint = NSPoint(
            x: clampedX - screenFrame.minX,
            y: clampedY - screenFrame.minY
        )
        wheelView.activeIndex = nil
        wheelView.needsDisplay = true
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.dismiss()
            self.overlayDelegate?.radialOverlayDidCancel(self)
        }
        orderFrontRegardless()
        makeKey()
    }

    private static func summary(for files: [URL]) -> String {
        guard files.count == 1 else { return "\(files.count) file" }
        return files[0].deletingPathExtension().lastPathComponent
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        orderOut(nil)
        files.removeAll()
        items.removeAll()
        wheelView.activeIndex = nil
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
        overlayDelegate?.radialOverlayDidCancel(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            cancelOperation(event)
        case 36, 76:
            activateKeyboardSelection()
        case 123, 125:
            moveSelection(by: -1)
        case 124, 126:
            moveSelection(by: 1)
        default:
            if let number = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(number) {
                let index = number - 1
                if items.indices.contains(index) {
                    wheelView.activeIndex = index
                    wheelView.needsDisplay = true
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }

    private func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        let current = wheelView.activeIndex ?? (offset > 0 ? -1 : 0)
        wheelView.activeIndex = (current + offset + items.count) % items.count
        wheelView.needsDisplay = true
    }

    private func activateKeyboardSelection() {
        guard let index = wheelView.activeIndex, items.indices.contains(index) else { return }
        let item = items[index]
        let selectedFiles = files
        let selectedMode = mode
        dismiss()
        overlayDelegate?.radialOverlay(self, didDrop: selectedFiles, item: item, mode: selectedMode)
    }

    private func selectedItem(at point: NSPoint) -> WheelItem? {
        let center = wheelView.centerPoint
        guard case let .sector(index) = RadialHitTesting.hit(point: point, center: center, sectorCount: items.count, geometry: geometry), items.indices.contains(index) else { return nil }
        return items[index]
    }
}

extension RadialOverlay: NSDraggingDestination {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        wheelView.update(point: sender.draggingLocation)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        wheelView.update(point: sender.draggingLocation)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        wheelView.activeIndex = nil
        wheelView.needsDisplay = true
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let item = selectedItem(at: sender.draggingLocation) else {
            dismiss()
            overlayDelegate?.radialOverlayDidCancel(self)
            return false
        }
        let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        let urls = objects.compactMap { $0 as URL }
        guard !urls.isEmpty else { return false }
        dismiss()
        overlayDelegate?.radialOverlay(self, didDrop: urls, item: item, mode: mode)
        return true
    }
}

final class RadialOverlayView: NSView {
    weak var delegate: RadialOverlay?
    var items: [WheelItem] = []
    var mode: WheelMode = .convert
    var selectionSummary = "File"
    var activeIndex: Int?
    var centerPoint = NSPoint.zero
    private let geometry = RadialGeometry()

    override var isFlipped: Bool { false }

    func update(point: NSPoint) {
        let center = centerPoint
        if case let .sector(index) = RadialHitTesting.hit(point: point, center: center, sectorCount: items.count, geometry: geometry) {
            activeIndex = index
        } else {
            activeIndex = nil
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let center = centerPoint
        let count = max(items.count, 1)
        let step = 360.0 / CGFloat(count)
        let innerRadius = CGFloat(geometry.innerRadius)
        let outerRadius = CGFloat(geometry.outerRadius)

        let canvasDiameter = CGFloat(geometry.discRadius) * 2
        let canvas = NSBezierPath(ovalIn: NSRect(x: center.x - canvasDiameter / 2, y: center.y - canvasDiameter / 2, width: canvasDiameter, height: canvasDiameter))
        NSColor(calibratedWhite: 0.035, alpha: 0.82).setFill()
        canvas.fill()
        NSColor(calibratedWhite: 1, alpha: 0.20).setStroke()
        canvas.lineWidth = 1.2
        canvas.stroke()

        for index in items.indices {
            let midpoint = 90.0 - CGFloat(index) * step
            let gap = CGFloat(geometry.angularGapDegrees)
            let start = midpoint + step / 2 - gap
            let end = midpoint - step / 2 + gap
            let path = annularPath(center: center, innerRadius: innerRadius, outerRadius: outerRadius, startAngle: start, endAngle: end)
            let isActive = index == activeIndex
            let idleColor = NSColor(calibratedWhite: 0.16, alpha: 0.90)
            let activeColor = NSColor(calibratedRed: 0.16, green: 0.43, blue: 0.92, alpha: 0.98)
            (isActive ? activeColor : idleColor).setFill()
            path.fill()
            (isActive ? NSColor(calibratedRed: 0.58, green: 0.80, blue: 1.0, alpha: 0.95) : NSColor(calibratedWhite: 1, alpha: 0.16)).setStroke()
            path.lineWidth = isActive ? 1.6 : 1
            path.lineJoinStyle = .round
            path.stroke()

            let mid = midpoint * .pi / 180
            let labelRadius = (innerRadius + outerRadius) / 2
            let item = items[index]
            let text = NSString(string: item.title.uppercased())
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: count > 8 ? 9 : 10.5, weight: isActive ? .bold : .semibold),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: isActive ? 1 : 0.92)
            ]
            let size = text.size(withAttributes: attributes)
            let labelCenter = NSPoint(x: center.x + Darwin.cos(mid) * labelRadius, y: center.y + Darwin.sin(mid) * labelRadius)
            let iconSize: CGFloat = count > 8 ? 16 : 18
            if let icon = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil) {
                icon.isTemplate = true
                let iconRect = NSRect(x: labelCenter.x - iconSize / 2, y: labelCenter.y + 2, width: iconSize, height: iconSize)
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: isActive ? 1 : 0.86)
            }
            let point = NSPoint(x: labelCenter.x - size.width / 2, y: labelCenter.y - size.height - 4)
            text.draw(at: point, withAttributes: attributes)
        }

        let hubRect = NSRect(x: center.x - 52, y: center.y - 32, width: 104, height: 64)
        let hub = NSBezierPath(roundedRect: hubRect, xRadius: 18, yRadius: 18)
        NSColor(calibratedWhite: 0.08, alpha: 0.96).setFill()
        hub.fill()
        NSColor(calibratedWhite: 1, alpha: 0.22).setStroke()
        hub.lineWidth = 1.2
        hub.stroke()

        let modeTitle = mode == .convert ? "KONVERSI" : mode == .tools ? "ALAT" : "AKSI"
        let modeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.55, green: 0.78, blue: 1, alpha: 1)
        ]
        let modeSize = modeTitle.size(withAttributes: modeAttributes)
        modeTitle.draw(at: NSPoint(x: center.x - modeSize.width / 2, y: center.y + 11), withAttributes: modeAttributes)

        let summary = NSString(string: selectionSummary)
        let summaryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let summaryParagraph = NSMutableParagraphStyle()
        summaryParagraph.alignment = .center
        summaryParagraph.lineBreakMode = .byTruncatingMiddle
        var summaryAttributesWithLayout = summaryAttributes
        summaryAttributesWithLayout[.paragraphStyle] = summaryParagraph
        let summaryRect = NSRect(x: hubRect.minX + 8, y: center.y - 14, width: hubRect.width - 16, height: 20)
        summary.draw(in: summaryRect, withAttributes: summaryAttributesWithLayout)

        let hint = NSString(string: "LEPAS  •  ESC BATAL")
        let hintAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.42)
        ]
        let hintSize = hint.size(withAttributes: hintAttributes)
        hint.draw(at: NSPoint(x: center.x - hintSize.width / 2, y: center.y - CGFloat(geometry.discRadius) - 18), withAttributes: hintAttributes)
    }

    private func annularPath(center: NSPoint, innerRadius: CGFloat, outerRadius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x + Darwin.cos(startAngle * .pi / 180) * outerRadius, y: center.y + Darwin.sin(startAngle * .pi / 180) * outerRadius))
        path.appendArc(withCenter: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        path.line(to: NSPoint(x: center.x + Darwin.cos(endAngle * .pi / 180) * innerRadius, y: center.y + Darwin.sin(endAngle * .pi / 180) * innerRadius))
        path.appendArc(withCenter: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: false)
        path.close()
        return path
    }
}
