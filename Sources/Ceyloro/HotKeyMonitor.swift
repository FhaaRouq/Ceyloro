import AppKit
import ApplicationServices

final class HotKeyMonitor {
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    var onTrigger: (() -> Void)?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start(promptForAccessibility: Bool = false) {
        if promptForAccessibility && !AXIsProcessTrusted() {
            Self.requestAccessibilityPermission()
        }
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

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
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
        guard event.keyCode == 49 && flags == .shift else { return false }

        // Guard against inline text editing in Finder (e.g. renaming file or typing in search/filter field)
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
           let element = focusedElement {
            var roleValue: AnyObject?
            if AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String {
                if role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String) {
                    return false
                }
            }
        }

        return true
    }
}

enum FinderSelectionResult: Equatable {
    case success([URL])
    case noSelection
    case permissionDenied(reason: String)
    case scriptError(String)
}

final class FinderSelectionReader {
    func readSelection() -> FinderSelectionResult {
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
        guard let script = NSAppleScript(source: source) else {
            return .scriptError("Gagal menginisialisasi AppleScript.")
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let errorNumber = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            let errorMessage = (error[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
            if errorNumber == -1743 || errorNumber == -10004 || errorMessage.contains("Not authorized") || errorMessage.contains("not permitted") {
                return .permissionDenied(reason: "Izin Otomatisasi (Apple Events) untuk mengontrol Finder belum diberikan.")
            }
            return .scriptError("\(errorMessage) (kode: \(errorNumber))")
        }
        guard result.numberOfItems > 0 else { return .noSelection }
        var urls: [URL] = []
        for index in 1...result.numberOfItems {
            guard let path = result.atIndex(index)?.stringValue else { continue }
            urls.append(URL(fileURLWithPath: path))
        }
        return urls.isEmpty ? .noSelection : .success(urls)
    }

    func selectedFiles() -> [URL] {
        if case .success(let files) = readSelection() {
            return files
        }
        return []
    }
}
