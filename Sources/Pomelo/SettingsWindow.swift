import AppKit
import PomeloCore
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    private let folderLabel = NSTextField(labelWithString: "")
    private let multiPagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let jpgQualitySlider = NSSlider(value: 0.92, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let heicQualitySlider = NSSlider(value: 0.92, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let jpgQualityLabel = NSTextField(labelWithString: "")
    private let heicQualityLabel = NSTextField(labelWithString: "")
    private let loginButton = NSButton(checkboxWithTitle: "Mulai saat login", target: nil, action: nil)
    private let mergeAskButton = NSButton(checkboxWithTitle: "Tanyakan opsi saat menggabungkan gambar ke PDF", target: nil, action: nil)

    convenience init() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 470))
        let window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Pengaturan Pomelo"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentView = content
        self.init(window: window)

        let heading = NSTextField(labelWithString: "Preferensi")
        heading.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 420, width: 470, height: 28)
        content.addSubview(heading)

        let folderTitle = NSTextField(labelWithString: "Folder output")
        folderTitle.frame = NSRect(x: 24, y: 376, width: 120, height: 20)
        content.addSubview(folderTitle)
        folderLabel.frame = NSRect(x: 24, y: 348, width: 370, height: 22)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.usesSingleLineMode = true
        content.addSubview(folderLabel)
        let choose = NSButton(title: "Pilih…", target: self, action: #selector(chooseFolder))
        choose.frame = NSRect(x: 420, y: 344, width: 76, height: 30)
        content.addSubview(choose)
        let reset = NSButton(title: "Reset", target: self, action: #selector(resetFolder))
        reset.frame = NSRect(x: 340, y: 344, width: 70, height: 30)
        content.addSubview(reset)

        let multiPageTitle = NSTextField(labelWithString: "Hasil multi-halaman")
        multiPageTitle.frame = NSRect(x: 24, y: 298, width: 170, height: 20)
        content.addSubview(multiPageTitle)
        multiPagePopup.addItems(withTitles: ["Folder", "ZIP"])
        multiPagePopup.frame = NSRect(x: 250, y: 292, width: 150, height: 28)
        multiPagePopup.target = self
        multiPagePopup.action = #selector(multiPageChanged)
        content.addSubview(multiPagePopup)

        let jpgTitle = NSTextField(labelWithString: "Kualitas JPG")
        jpgTitle.frame = NSRect(x: 24, y: 252, width: 130, height: 20)
        content.addSubview(jpgTitle)
        jpgQualitySlider.frame = NSRect(x: 160, y: 250, width: 250, height: 20)
        jpgQualitySlider.target = self
        jpgQualitySlider.action = #selector(qualityChanged)
        content.addSubview(jpgQualitySlider)
        jpgQualityLabel.frame = NSRect(x: 420, y: 252, width: 70, height: 20)
        content.addSubview(jpgQualityLabel)

        let heicTitle = NSTextField(labelWithString: "Kualitas HEIC")
        heicTitle.frame = NSRect(x: 24, y: 212, width: 130, height: 20)
        content.addSubview(heicTitle)
        heicQualitySlider.frame = NSRect(x: 160, y: 210, width: 250, height: 20)
        heicQualitySlider.target = self
        heicQualitySlider.action = #selector(qualityChanged)
        content.addSubview(heicQualitySlider)
        heicQualityLabel.frame = NSRect(x: 420, y: 212, width: 70, height: 20)
        content.addSubview(heicQualityLabel)

        loginButton.frame = NSRect(x: 24, y: 164, width: 240, height: 24)
        loginButton.target = self
        loginButton.action = #selector(loginChanged)
        content.addSubview(loginButton)
        mergeAskButton.frame = NSRect(x: 24, y: 128, width: 450, height: 24)
        mergeAskButton.target = self
        mergeAskButton.action = #selector(mergeAskChanged)
        content.addSubview(mergeAskButton)

        let note = NSTextField(wrappingLabelWithString: "Semua pemrosesan berlangsung lokal. File asli tidak pernah diubah atau ditimpa.")
        note.frame = NSRect(x: 24, y: 42, width: 470, height: 54)
        note.textColor = .secondaryLabelColor
        content.addSubview(note)
        updateControls()
    }

    override func showWindow(_ sender: Any?) {
        updateControls()
        super.showWindow(sender)
    }

    @objc private func chooseFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            UserDefaults.standard.set(url.path, forKey: "outputDirectory")
            self?.updateFolderLabel()
        }
    }

    @objc private func resetFolder() {
        UserDefaults.standard.removeObject(forKey: "outputDirectory")
        updateFolderLabel()
    }

    @objc private func multiPageChanged() {
        let value = multiPagePopup.indexOfSelectedItem == 1 ? MultiPageOutput.zip.rawValue : MultiPageOutput.folder.rawValue
        UserDefaults.standard.set(value, forKey: "multiPageOutput")
    }

    @objc private func qualityChanged() {
        UserDefaults.standard.set(jpgQualitySlider.doubleValue, forKey: "jpgQuality")
        UserDefaults.standard.set(heicQualitySlider.doubleValue, forKey: "heicQuality")
        updateQualityLabels()
    }

    @objc private func loginChanged() {
        do {
            if loginButton.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginButton.state = .off
            showError("Pengaturan mulai saat login gagal: \(error.localizedDescription)")
        }
    }

    @objc private func mergeAskChanged() {
        UserDefaults.standard.set(mergeAskButton.state == .on, forKey: "mergePDF.askEveryTime")
    }

    private func updateControls() {
        updateFolderLabel()
        let output = MultiPageOutput(rawValue: UserDefaults.standard.string(forKey: "multiPageOutput") ?? "") ?? .folder
        multiPagePopup.selectItem(at: output == .zip ? 1 : 0)
        jpgQualitySlider.doubleValue = UserDefaults.standard.object(forKey: "jpgQuality") as? Double ?? 0.92
        heicQualitySlider.doubleValue = UserDefaults.standard.object(forKey: "heicQuality") as? Double ?? 0.92
        updateQualityLabels()
        loginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
        mergeAskButton.state = (UserDefaults.standard.object(forKey: "mergePDF.askEveryTime") as? Bool ?? true) ? .on : .off
    }

    private func updateFolderLabel() {
        let savedFolder = UserDefaults.standard.string(forKey: "outputDirectory")
        folderLabel.stringValue = savedFolder.map { "Tersimpan: \($0)" } ?? "Di samping file asli"
    }

    private func updateQualityLabels() {
        jpgQualityLabel.stringValue = "\(Int(jpgQualitySlider.doubleValue * 100))%"
        heicQualityLabel.stringValue = "\(Int(heicQualitySlider.doubleValue * 100))%"
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Pomelo"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
