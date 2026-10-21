import AppKit
import Darwin
import CeyloroCore

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
            case .txt, .srt, .vtt: return "doc.text"
            case .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff: return "waveform"
            case .mp4, .mov, .mkv, .webm, .avi, .wmv, .gif: return "film"
            case .zip, .tar, .gzip: return "archivebox"
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
    private var countdownTimer: Timer?
    private var dismissStartDate: Date?
    private var exitDebounceTimer: Timer?

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
        wheelView.fileCount = files.count
        wheelView.selectionSummary = Self.summary(for: files)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let selectedScreenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = screen?.visibleFrame ?? selectedScreenFrame
        let screenFrame = Self.combinedScreenFrame(screens: NSScreen.screens.map(\.frame), fallback: selectedScreenFrame)
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
        wheelView.isHubActive = false
        wheelView.dismissCountdownFraction = nil
        wheelView.needsDisplay = true
        dismissTimer?.invalidate()
        countdownTimer?.invalidate()
        dismissStartDate = Date()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.dismiss()
            self.overlayDelegate?.radialOverlayDidCancel(self)
        }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.dismissStartDate else { return }
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= 25.0 {
                let fraction = min(max((30.0 - elapsed) / 5.0, 0), 1.0)
                self.wheelView.dismissCountdownFraction = fraction
                self.wheelView.needsDisplay = true
            }
        }
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    static func combinedScreenFrame(screens: [NSRect], fallback: NSRect = NSRect(x: 0, y: 0, width: 1440, height: 900)) -> NSRect {
        guard let first = screens.first else { return fallback }
        return screens.dropFirst().reduce(first) { $0.union($1) }
    }

    private static func summary(for files: [URL]) -> String {
        guard files.count == 1 else { return "\(files.count) file" }
        return files[0].deletingPathExtension().lastPathComponent
    }

    func dismiss(animated: Bool = true) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        dismissStartDate = nil
        exitDebounceTimer?.invalidate()
        exitDebounceTimer = nil
        files.removeAll()
        items.removeAll()
        wheelView.activeIndex = nil
        wheelView.isHubActive = false
        wheelView.dismissCountdownFraction = nil
        if animated && isVisible {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.10
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self else { return }
                self.orderOut(nil)
                self.alphaValue = 1
            })
        } else {
            orderOut(nil)
            alphaValue = 1
        }
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

    func activateKeyboardSelection() {
        guard let index = wheelView.activeIndex else { return }
        selectItem(at: index)
    }

    func selectItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        let selectedFiles = files
        let selectedMode = mode
        dismiss()
        overlayDelegate?.radialOverlay(self, didDrop: selectedFiles, item: item, mode: selectedMode)
    }

    func dismissAndCancel() {
        dismiss()
        overlayDelegate?.radialOverlayDidCancel(self)
    }

    private func selectedItem(at point: NSPoint) -> WheelItem? {
        let center = wheelView.centerPoint
        guard case let .sector(index) = RadialHitTesting.hit(point: point, center: center, sectorCount: items.count, geometry: geometry), items.indices.contains(index) else { return nil }
        return items[index]
    }
}

extension RadialOverlay: NSDraggingDestination {
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        exitDebounceTimer?.invalidate()
        exitDebounceTimer = nil
        wheelView.update(point: sender.draggingLocation)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        exitDebounceTimer?.invalidate()
        exitDebounceTimer = nil
        wheelView.update(point: sender.draggingLocation)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        exitDebounceTimer?.invalidate()
        exitDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.wheelView.activeIndex = nil
            self.wheelView.isHubActive = false
            self.wheelView.needsDisplay = true
        }
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
    var items: [WheelItem] = [] {
        didSet {
            accessibilityChildrenCache.removeAll()
        }
    }
    var mode: WheelMode = .convert {
        didSet {
            accessibilityChildrenCache.removeAll()
        }
    }
    var selectionSummary = "File"
    var fileCount = 1
    var isHubActive = false
    var dismissCountdownFraction: Double?
    var activeIndex: Int? {
        didSet {
            guard activeIndex != oldValue else { return }
            if let activeIndex, accessibilityChildrenCache.indices.contains(activeIndex) {
                NSAccessibility.post(element: accessibilityChildrenCache[activeIndex], notification: .focusedUIElementChanged)
            }
        }
    }
    var centerPoint = NSPoint.zero
    private let geometry = RadialGeometry()
    private var accessibilityChildrenCache: [RadialSectorAccessibilityElement] = []

    private var modeAccentColor: NSColor {
        switch mode {
        case .convert:
            return NSColor(calibratedRed: 0.35, green: 0.72, blue: 1.0, alpha: 1)
        case .actions:
            return NSColor(calibratedRed: 1.0, green: 0.65, blue: 0.25, alpha: 1)
        case .tools:
            return NSColor(calibratedWhite: 0.72, alpha: 1)
        }
    }

    private var activeSectorFillColor: NSColor {
        switch mode {
        case .convert:
            return NSColor(calibratedRed: 0.16, green: 0.43, blue: 0.92, alpha: 0.98)
        case .actions:
            return NSColor(calibratedRed: 0.88, green: 0.45, blue: 0.10, alpha: 0.98)
        case .tools:
            return NSColor(calibratedWhite: 0.30, alpha: 0.98)
        }
    }

    private var activeSectorStrokeColor: NSColor {
        switch mode {
        case .convert:
            return NSColor(calibratedRed: 0.58, green: 0.80, blue: 1.0, alpha: 0.95)
        case .actions:
            return NSColor(calibratedRed: 1.0, green: 0.75, blue: 0.40, alpha: 0.95)
        case .tools:
            return NSColor(calibratedWhite: 0.70, alpha: 0.95)
        }
    }

    override var isFlipped: Bool { false }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? {
        "Menu Radial Ceyloro - \(mode == .convert ? "Konversi" : mode == .tools ? "Alat" : "Aksi")"
    }

    override func accessibilityChildren() -> [Any]? {
        let titlesMatch = accessibilityChildrenCache.count == items.count &&
            zip(accessibilityChildrenCache, items).allSatisfy { $0.title == $1.title }
        if !titlesMatch {
            accessibilityChildrenCache = items.enumerated().map { index, item in
                RadialSectorAccessibilityElement(index: index, title: item.title, parentView: self)
            }
        }
        return accessibilityChildrenCache
    }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeAlways, .mouseMoved, .mouseEnteredAndExited]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        update(point: location)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let hit = RadialHitTesting.hit(point: location, center: centerPoint, sectorCount: items.count, geometry: geometry)
        switch hit {
        case .sector(let index):
            activeIndex = index
            needsDisplay = true
            delegate?.selectItem(at: index)
        case .outside, .hub:
            delegate?.dismissAndCancel()
        }
    }

    func update(point: NSPoint) {
        let center = centerPoint
        let hit = RadialHitTesting.hit(point: point, center: center, sectorCount: items.count, geometry: geometry)
        switch hit {
        case .sector(let index):
            activeIndex = index
            isHubActive = false
        case .hub:
            activeIndex = nil
            isHubActive = true
        case .outside:
            activeIndex = nil
            isHubActive = false
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
            let activeColor = activeSectorFillColor
            (isActive ? activeColor : idleColor).setFill()
            path.fill()
            (isActive ? activeSectorStrokeColor : NSColor(calibratedWhite: 1, alpha: 0.16)).setStroke()
            path.lineWidth = isActive ? 1.6 : 1
            path.lineJoinStyle = .round
            path.stroke()

            let mid = midpoint * .pi / 180
            let item = items[index]
            let baseFontSize: CGFloat = count > 12 ? 8.5 : count > 10 ? 9.0 : count > 8 ? 9.5 : 11.0

            // Available angular width chord at text radius to prevent clipping and overlap
            let textRadius = count > 8 ? (innerRadius * 0.65 + outerRadius * 0.35) - 3 : (innerRadius + outerRadius) / 2 - 10
            let sectorChord = 2.0 * textRadius * Darwin.sin((step - CGFloat(geometry.angularGapDegrees)) * .pi / 360.0)
            let availableTextWidth = max(sectorChord * 0.88, 22.0)

            var chosenFont = NSFont.systemFont(ofSize: baseFontSize, weight: isActive ? .bold : .semibold)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: chosenFont,
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: isActive ? 1.0 : 0.92)
            ]
            let text = NSString(string: item.title.uppercased())
            var size = text.size(withAttributes: attributes)

            // If text exceeds available sector width, scale font size down dynamically
            if size.width > availableTextWidth && baseFontSize > 7.5 {
                let scaledSize = max(baseFontSize * (availableTextWidth / size.width), 7.5)
                chosenFont = NSFont.systemFont(ofSize: scaledSize, weight: isActive ? .bold : .semibold)
                attributes[.font] = chosenFont
                size = text.size(withAttributes: attributes)
            }

            // When there are many sectors, stagger the icon outward and text inward along the radial vector
            // to maximize available horizontal width in narrow sectors
            let iconRadius = count > 8 ? (innerRadius * 0.40 + outerRadius * 0.60) + 7 : (innerRadius + outerRadius) / 2 + 10
            let iconCenter = NSPoint(x: center.x + Darwin.cos(mid) * iconRadius, y: center.y + Darwin.sin(mid) * iconRadius)
            let textCenter = NSPoint(x: center.x + Darwin.cos(mid) * textRadius, y: center.y + Darwin.sin(mid) * textRadius)

            let iconSize: CGFloat = count > 10 ? 14 : count > 8 ? 16 : 18
            if let icon = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: item.title) {
                icon.isTemplate = true
                let iconRect = NSRect(x: iconCenter.x - iconSize / 2, y: iconCenter.y - iconSize / 2, width: iconSize, height: iconSize)
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: isActive ? 1.0 : 0.88)
            }
            let point = NSPoint(x: textCenter.x - size.width / 2, y: textCenter.y - size.height / 2)
            text.draw(at: point, withAttributes: attributes)
        }

        let hubRect = NSRect(x: center.x - 52, y: center.y - 32, width: 104, height: 64)
        let hub = NSBezierPath(roundedRect: hubRect, xRadius: 18, yRadius: 18)
        let hubBgColor = isHubActive ? NSColor(calibratedWhite: 0.14, alpha: 0.98) : NSColor(calibratedWhite: 0.08, alpha: 0.96)
        hubBgColor.setFill()
        hub.fill()
        let hubStrokeColor = isHubActive ? modeAccentColor.withAlphaComponent(0.85) : NSColor(calibratedWhite: 1, alpha: 0.22)
        hubStrokeColor.setStroke()
        hub.lineWidth = isHubActive ? 2.0 : 1.2
        hub.stroke()

        if let fraction = dismissCountdownFraction, fraction > 0 {
            let countdownPath = NSBezierPath(roundedRect: hubRect.insetBy(dx: -3, dy: -3), xRadius: 21, yRadius: 21)
            NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.35, alpha: CGFloat(0.4 + 0.5 * (1.0 - fraction))).setStroke()
            countdownPath.lineWidth = 1.5
            countdownPath.stroke()
        }

        let modeTitle: String
        switch mode {
        case .convert:
            modeTitle = "KONVERSI"
        case .actions:
            modeTitle = "AKSI"
        case .tools:
            modeTitle = "ALAT • SEGERA HADIR"
        }
        let modeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: mode == .tools ? 7.5 : 8.5, weight: .bold),
            .foregroundColor: modeAccentColor
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

        if fileCount > 1, let stackIcon = NSImage(systemSymbolName: "doc.on.doc.fill", accessibilityDescription: "Banyak berkas") {
            stackIcon.isTemplate = true
            let iconSize: CGFloat = 11
            let spacing: CGFloat = 5
            let measuredTextWidth = summary.size(withAttributes: summaryAttributes).width
            let maxAvailableWidth = hubRect.width - 16
            let totalContentWidth = min(iconSize + spacing + measuredTextWidth, maxAvailableWidth)
            let startX = center.x - totalContentWidth / 2
            let iconRect = NSRect(x: startX, y: center.y - 9.5, width: iconSize, height: iconSize)
            stackIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.95)

            let textRect = NSRect(x: startX + iconSize + spacing, y: center.y - 14, width: totalContentWidth - iconSize - spacing, height: 20)
            let leftAlignedParagraph = NSMutableParagraphStyle()
            leftAlignedParagraph.alignment = .left
            leftAlignedParagraph.lineBreakMode = .byTruncatingMiddle
            var leftAttributes = summaryAttributes
            leftAttributes[.paragraphStyle] = leftAlignedParagraph
            summary.draw(in: textRect, withAttributes: leftAttributes)
        } else {
            let summaryRect = NSRect(x: hubRect.minX + 8, y: center.y - 14, width: hubRect.width - 16, height: 20)
            summary.draw(in: summaryRect, withAttributes: summaryAttributesWithLayout)
        }

        let hint = NSString(string: "LEPAS  •  1–9 PILIH  •  ESC BATAL")
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

final class RadialSectorAccessibilityElement: NSAccessibilityElement {
    let index: Int
    let title: String
    weak var parentView: RadialOverlayView?

    init(index: Int, title: String, parentView: RadialOverlayView) {
        self.index = index
        self.title = title
        self.parentView = parentView
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        setAccessibilityParent(parentView)
    }

    override func accessibilityValue() -> Any? {
        parentView?.activeIndex == index ? "Terpilih" : nil
    }

    override func accessibilityPerformPress() -> Bool {
        parentView?.activeIndex = index
        parentView?.delegate?.activateKeyboardSelection()
        return true
    }
}
