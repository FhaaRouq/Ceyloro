import AppKit

final class ToastWindow: NSPanel {
    private static var activeToast: ToastWindow?

    static func show(message: String, systemImage: String = "info.circle", duration: TimeInterval = 2.4) {
        DispatchQueue.main.async {
            activeToast?.close()
            let toast = ToastWindow(message: message, systemImage: systemImage)
            activeToast = toast
            toast.present(duration: duration)
        }
    }

    private init(message: String, systemImage: String) {
        let padding: CGFloat = 16
        let iconSize: CGFloat = 18

        let iconView = NSImageView()
        if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
            image.isTemplate = true
            iconView.image = image
            iconView.contentTintColor = NSColor(calibratedRed: 0.35, green: 0.72, blue: 1.0, alpha: 1)
        }
        iconView.frame = NSRect(x: padding, y: padding - 1, width: iconSize, height: iconSize)

        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        let labelSize = label.sizeThatFits(NSSize(width: 420, height: 100))
        label.frame = NSRect(x: padding + iconSize + 10, y: padding - 2, width: ceil(labelSize.width), height: max(ceil(labelSize.height), 20))

        let totalWidth = padding + iconSize + 10 + label.frame.width + padding
        let totalHeight = max(label.frame.height + padding * 2 - 4, 46)

        let frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        ignoresMouseEvents = true

        let effectView = NSVisualEffectView(frame: frame)
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1.0
        effectView.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.15).cgColor

        effectView.addSubview(iconView)
        effectView.addSubview(label)
        contentView = effectView
    }

    private func present(duration: TimeInterval) {
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLoc) } ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let originX = screenFrame.midX - frame.width / 2
        let originY = screenFrame.maxY - frame.height - 40
        setFrameOrigin(NSPoint(x: originX, y: originY))

        alphaValue = 0
        orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 1
        } completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    self.animator().alphaValue = 0
                } completionHandler: {
                    self.close()
                    if ToastWindow.activeToast === self {
                        ToastWindow.activeToast = nil
                    }
                }
            }
        }
    }
}
