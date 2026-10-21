import AppKit

final class DragMonitor {
    var onWheelChange: (([URL], NSPoint, NSEvent.ModifierFlags) -> Void)?
    var onDragEnd: (() -> Void)?
    private let pasteboard = NSPasteboard(name: .drag)
    private var timer: Timer?
    private var wasDragging = false
    private var mouseWasDown = false
    private var baselineChangeCount = -1
    private var downPoint = NSPoint.zero
    private var lastChangeCount = -1
    private var lastFlags: NSEvent.ModifierFlags = []
    private var lastURLs: [URL] = []
    private var dragActivity: NSObjectProtocol?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    func start() {
        guard timer == nil else { return }
        installMouseMonitors()
        installTimer(interval: 1.0 / 20.0)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endDragActivity()
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func installMouseMonitors() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.recordMouseDown()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.recordMouseDown()
        }
    }

    private func recordMouseDown() {
        mouseWasDown = true
        wasDragging = false
        baselineChangeCount = pasteboard.changeCount
        lastChangeCount = -1
        lastFlags = []
        lastURLs.removeAll()
        downPoint = NSEvent.mouseLocation
        if dragActivity == nil {
            dragActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "Ceyloro drag monitoring"
            )
        }
        useActiveDragTimer()
    }

    private func poll() {
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0
        guard mouseDown else {
            if mouseWasDown {
                mouseWasDown = false
                baselineChangeCount = -1
                lastChangeCount = -1
                endDragActivity()
                restoreIdleTimer()
            }
            if wasDragging {
                wasDragging = false
                lastURLs.removeAll()
                lastFlags = []
                onDragEnd?()
            }
            return
        }

        if !mouseWasDown {
            recordMouseDown()
            return
        }

        let point = NSEvent.mouseLocation
        let changeCount = pasteboard.changeCount
        guard hypot(point.x - downPoint.x, point.y - downPoint.y) > 6,
              changeCount != baselineChangeCount else { return }

        let flags = NSEvent.modifierFlags
        guard flags.contains(.shift) else { return }
        let previousURLs = lastURLs
        if changeCount != lastChangeCount {
            lastChangeCount = changeCount
            lastURLs = readURLs()
        }
        let urls = lastURLs
        guard !urls.isEmpty else { return }
        let changed = !wasDragging || flags != lastFlags || urls != previousURLs
        if changed {
            wasDragging = true
            lastFlags = flags
            lastURLs = urls
            onWheelChange?(urls, NSEvent.mouseLocation, flags)
        }
    }

    private func readURLs() -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        return objects.compactMap { $0 as URL }
    }

    private func useActiveDragTimer() {
        guard let timer, timer.timeInterval > 1.0 / 30.0 else { return }
        timer.invalidate()
        installTimer(interval: 1.0 / 60.0)
    }

    private func restoreIdleTimer() {
        guard let timer, timer.timeInterval < 1.0 / 30.0 else { return }
        timer.invalidate()
        installTimer(interval: 1.0 / 20.0)
    }

    private func installTimer(interval: TimeInterval) {
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    private func endDragActivity() {
        guard let dragActivity else { return }
        ProcessInfo.processInfo.endActivity(dragActivity)
        self.dragActivity = nil
    }
}
