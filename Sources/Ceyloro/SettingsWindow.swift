import AppKit
import CeyloroCore
import ServiceManagement

extension Notification.Name {
    static let ceyloroEngineSettingsChanged = Notification.Name("CeyloroEngineSettingsChanged")
}

final class SettingsWindowController: NSWindowController {
    private let folderLabel = NSTextField(labelWithString: "")
    private let multiPagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let jpgQualitySlider = NSSlider(value: 0.92, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let heicQualitySlider = NSSlider(value: 0.92, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let jpgQualityLabel = NSTextField(labelWithString: "")
    private let heicQualityLabel = NSTextField(labelWithString: "")
    private let loginButton = NSButton(checkboxWithTitle: "Mulai saat login", target: nil, action: nil)
    private let mergeAskButton = NSButton(checkboxWithTitle: "Tanyakan opsi saat menggabungkan gambar ke PDF", target: nil, action: nil)
    private let ffmpegPathField = NSTextField(string: "")

    convenience init() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 540))
        let window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Pengaturan Ceyloro"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentView = content
        self.init(window: window)

        let heading = NSTextField(labelWithString: "Preferensi")
        heading.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 486, width: 472, height: 28)
        content.addSubview(heading)

        let folderTitle = NSTextField(labelWithString: "Folder output")
        folderTitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        folderTitle.frame = NSRect(x: 24, y: 448, width: 140, height: 20)
        content.addSubview(folderTitle)
        folderLabel.frame = NSRect(x: 24, y: 418, width: 318, height: 22)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.usesSingleLineMode = true
        folderLabel.textColor = .secondaryLabelColor
        content.addSubview(folderLabel)
        let reset = NSButton(title: "Reset", target: self, action: #selector(resetFolder))
        reset.frame = NSRect(x: 348, y: 414, width: 70, height: 28)
        content.addSubview(reset)
        let choose = NSButton(title: "Pilih…", target: self, action: #selector(chooseFolder))
        choose.frame = NSRect(x: 422, y: 414, width: 74, height: 28)
        content.addSubview(choose)

        let multiPageTitle = NSTextField(labelWithString: "Hasil multi-halaman")
        multiPageTitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        multiPageTitle.frame = NSRect(x: 24, y: 370, width: 180, height: 20)
        content.addSubview(multiPageTitle)
        multiPagePopup.addItems(withTitles: ["Folder", "ZIP"])
        multiPagePopup.frame = NSRect(x: 280, y: 366, width: 140, height: 28)
        multiPagePopup.target = self
        multiPagePopup.action = #selector(multiPageChanged)
        content.addSubview(multiPagePopup)

        let jpgTitle = NSTextField(labelWithString: "Kualitas JPG")
        jpgTitle.frame = NSRect(x: 24, y: 326, width: 130, height: 20)
        content.addSubview(jpgTitle)
        jpgQualitySlider.frame = NSRect(x: 160, y: 324, width: 250, height: 20)
        jpgQualitySlider.target = self
        jpgQualitySlider.action = #selector(qualityChanged)
        content.addSubview(jpgQualitySlider)
        jpgQualityLabel.frame = NSRect(x: 420, y: 326, width: 60, height: 20)
        content.addSubview(jpgQualityLabel)

        let heicTitle = NSTextField(labelWithString: "Kualitas HEIC")
        heicTitle.frame = NSRect(x: 24, y: 286, width: 130, height: 20)
        content.addSubview(heicTitle)
        heicQualitySlider.frame = NSRect(x: 160, y: 284, width: 250, height: 20)
        heicQualitySlider.target = self
        heicQualitySlider.action = #selector(qualityChanged)
        content.addSubview(heicQualitySlider)
        heicQualityLabel.frame = NSRect(x: 420, y: 286, width: 60, height: 20)
        content.addSubview(heicQualityLabel)

        loginButton.frame = NSRect(x: 24, y: 240, width: 240, height: 22)
        loginButton.target = self
        loginButton.action = #selector(loginChanged)
        content.addSubview(loginButton)
        mergeAskButton.frame = NSRect(x: 24, y: 208, width: 472, height: 22)
        mergeAskButton.target = self
        mergeAskButton.action = #selector(mergeAskChanged)
        content.addSubview(mergeAskButton)

        let ffmpegTitle = NSTextField(labelWithString: "FFmpeg")
        ffmpegTitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        ffmpegTitle.frame = NSRect(x: 24, y: 164, width: 130, height: 20)
        content.addSubview(ffmpegTitle)
        ffmpegPathField.frame = NSRect(x: 24, y: 132, width: 318, height: 24)
        ffmpegPathField.placeholderString = "Otomatis (bundled atau PATH)"
        ffmpegPathField.lineBreakMode = .byTruncatingMiddle
        ffmpegPathField.usesSingleLineMode = true
        content.addSubview(ffmpegPathField)
        let chooseFFmpeg = NSButton(title: "Pilih…", target: self, action: #selector(chooseFFmpeg))
        chooseFFmpeg.frame = NSRect(x: 348, y: 130, width: 70, height: 28)
        content.addSubview(chooseFFmpeg)
        let resetFFmpeg = NSButton(title: "Otomatis", target: self, action: #selector(resetFFmpeg))
        resetFFmpeg.frame = NSRect(x: 422, y: 130, width: 74, height: 28)
        content.addSubview(resetFFmpeg)

        let note = NSTextField(wrappingLabelWithString: "Semua pemrosesan berlangsung lokal. File asli tidak pernah diubah atau ditimpa.")
        note.frame = NSRect(x: 24, y: 64, width: 472, height: 34)
        note.textColor = .secondaryLabelColor
        content.addSubview(note)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "Ceyloro v\(version) (\(build))")
        versionLabel.frame = NSRect(x: 24, y: 24, width: 472, height: 18)
        versionLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .center
        content.addSubview(versionLabel)

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

    @objc private func chooseFFmpeg() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Pilih"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            UserDefaults.standard.set(url.path, forKey: "ffmpegPath")
            self.ffmpegPathField.stringValue = url.path
            NotificationCenter.default.post(name: .ceyloroEngineSettingsChanged, object: nil)
        }
    }

    @objc private func resetFFmpeg() {
        UserDefaults.standard.removeObject(forKey: "ffmpegPath")
        ffmpegPathField.stringValue = ""
        NotificationCenter.default.post(name: .ceyloroEngineSettingsChanged, object: nil)
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
        ffmpegPathField.stringValue = UserDefaults.standard.string(forKey: "ffmpegPath") ?? ""
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
        alert.messageText = "Ceyloro"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
