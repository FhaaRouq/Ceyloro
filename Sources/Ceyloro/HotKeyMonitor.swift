import AppKit

final class HotKeyMonitor {
    var onTrigger: (() -> Void)?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start() {
        let handler: (NSEvent) -> NSEvent? = { [weak self] event in
            if Self.isFallbackHotKey(event) {
                self?.onTrigger?()
            }
            return event
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isFallbackHotKey(event) {
                self?.onTrigger?()
            }
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
    }

    private static func isFallbackHotKey(_ event: NSEvent) -> Bool {
        // The fallback shortcut is intended for Finder selections. Without
        // this guard, Shift+Space hijacks typing and shortcuts in every app.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 49 && flags == .shift
    }
}

final class FinderSelectionReader {
    func selectedFiles() -> [URL] {
        let source = """
        tell application "Finder"
            set selectedItems to selection
            set output to {}
            repeat with itemRef in selectedItems
                set end of output to POSIX path of (itemRef as alias)
            end repeat
            return output
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return [] }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, result.numberOfItems > 0 else { return [] }
        var urls: [URL] = []
        for index in 1...result.numberOfItems {
            guard let path = result.atIndex(index)?.stringValue else { continue }
            urls.append(URL(fileURLWithPath: path))
        }
        return urls
    }
}
