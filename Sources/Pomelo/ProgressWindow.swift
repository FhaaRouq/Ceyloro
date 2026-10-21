import AppKit
import PomeloCore

final class ProgressWindowController {
    private let window: NSPanel
    private let titleField: NSTextField
    private let progress: NSProgressIndicator
    private let cancelButton: NSButton
    private var jobID: UUID?
    private var cancelAction: ((UUID) -> Void)?
    private var showWorkItem: DispatchWorkItem?
    private var isVisible = false
    private var finishedBeforeShowing = false
    private static var cascadeIndex = 0

    init() {
        let frame = NSRect(x: 0, y: 0, width: 330, height: 92)
        window = NSPanel(contentRect: frame, styleMask: [.titled, .utilityWindow], backing: .buffered, defer: true)
        window.title = "Pomelo"
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        titleField = NSTextField(labelWithString: "Menunggu…")
        progress = NSProgressIndicator(frame: NSRect(x: 18, y: 40, width: 210, height: 16))
        cancelButton = NSButton(title: "Batal", target: nil, action: nil)
        let content = NSView(frame: frame)
        titleField.frame = NSRect(x: 18, y: 64, width: 290, height: 18)
        cancelButton.frame = NSRect(x: 242, y: 34, width: 70, height: 28)
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        content.addSubview(titleField)
        content.addSubview(progress)
        content.addSubview(cancelButton)
        window.contentView = content
    }

    func show(jobID: UUID, cancel: @escaping (UUID) -> Void) {
        self.jobID = jobID
        self.cancelAction = cancel
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        showWorkItem?.cancel()
        finishedBeforeShowing = false
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.finishedBeforeShowing else { return }
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let offset = CGFloat(Self.cascadeIndex % 5) * 28
            Self.cascadeIndex += 1
            let x = min(screenFrame.maxX - self.window.frame.width - 20, screenFrame.midX - self.window.frame.width / 2 + offset)
            let y = min(screenFrame.maxY - self.window.frame.height - 20, screenFrame.midY - self.window.frame.height / 2 - offset)
            self.window.setFrameOrigin(NSPoint(x: max(screenFrame.minX + 20, x), y: max(screenFrame.minY + 20, y)))
            self.window.orderFrontRegardless()
            self.isVisible = true
        }
        showWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    func update(_ snapshot: JobSnapshot) {
        titleField.stringValue = snapshot.message
        progress.doubleValue = snapshot.progress
        if snapshot.state == .completed || snapshot.state == .failed || snapshot.state == .cancelled {
            if !isVisible {
                finishedBeforeShowing = true
                showWorkItem?.cancel()
            } else {
                window.orderOut(nil)
                isVisible = false
            }
        }
    }

    @objc private func cancelPressed() {
        if let jobID { cancelAction?(jobID) }
    }
}
