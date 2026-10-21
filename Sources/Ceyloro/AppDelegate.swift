import AppKit
import CeyloroCore

final class AppDelegate: NSObject, NSApplicationDelegate, RadialOverlayDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = RadialOverlay()
    private let monitor = DragMonitor()
    private let hotKeyMonitor = HotKeyMonitor()
    private let finderSelectionReader = FinderSelectionReader()
    private let matrix = ConversionMatrix()
    private let runner = JobRunner()
    private let converter = ImageConverter()
    private let audioConverter = AudioConverter()
    private let videoConverter = VideoConverter()
    private let subtitleConverter = SubtitleConverter()
    private let archiveConverter = ArchiveConverter()
    private let engineProbe = RuntimeEngineProbe()
    private var progressWindows: [UUID: ProgressWindowController] = [:]
    private var settingsWindow: SettingsWindowController?
    private var pdfMergeWindow: PDFMergeWindowController?
    private var activeFiles: [URL] = []
    private var currentMode: WheelMode = .convert
    private var dragActivity: NSObjectProtocol?
    private let logURL: URL = {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Ceyloro", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("app.log")
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        cleanupOldTemporaryDirectories()
        rotateLogIfNeeded()
        dragActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Drag monitoring")
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        overlay.overlayDelegate = self
        monitor.onWheelChange = { [weak self] files, point, flags in self?.showWheel(files: files, at: point, flags: flags) }
        monitor.onDragEnd = { [weak self] in
            guard let self, self.overlay.isVisible else { return }
            // Give AppKit's dragging destination callback a turn to receive a valid drop.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard self.overlay.isVisible else { return }
                self.overlay.dismiss()
                self.activeFiles.removeAll()
            }
        }
        monitor.start()
        hotKeyMonitor.onTrigger = { [weak self] in self?.showWheelFromHotKey() }
        hotKeyMonitor.start()
        let engineStatus = engineProbe.inspect()
        log("Engine AVFoundation: tersedia; FFmpeg: \(engineStatus.ffmpegURL?.path ?? "tidak ditemukan")")
        log("Ceyloro started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotKeyMonitor.stop()
        if let dragActivity {
            ProcessInfo.processInfo.endActivity(dragActivity)
            self.dragActivity = nil
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = Bundle.main.image(forResource: "CeyloroMenuTemplate") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = image
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "circle.grid.3x3", accessibilityDescription: "Ceyloro")
        }
        statusItem.button?.toolTip = "Ceyloro"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Ceyloro aktif", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Pengaturan…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Tampilkan Log", action: #selector(showLogs), keyEquivalent: "l"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Keluar Ceyloro", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func showWheel(files: [URL], at point: NSPoint, flags: NSEvent.ModifierFlags) {
        activeFiles = files
        currentMode = flags.contains(.control) ? .actions : flags.contains(.option) ? .tools : .convert
        var items = wheelItems(for: files, mode: currentMode)
        if items.isEmpty {
            currentMode = .actions
            items = wheelItems(for: files, mode: .actions)
        }
        guard !items.isEmpty else { return }
        overlay.present(files: files, mode: currentMode, items: items, at: point)
    }

    private func showWheelFromHotKey() {
        let files = finderSelectionReader.selectedFiles()
        guard !files.isEmpty else {
            showError("Pilih satu atau beberapa file di Finder terlebih dahulu.")
            return
        }
        showWheel(files: files, at: NSEvent.mouseLocation, flags: [.shift])
    }

    private func wheelItems(for files: [URL], mode: WheelMode) -> [WheelItem] {
        switch mode {
        case .convert:
            let formats = matrix.commonTargets(for: files.map(FileFormat.detect(url:)))
            if files.allSatisfy({ FileFormat.detect(url: $0).kind == .audio }) {
                return audioConverter.supportedTargets(for: files, candidates: formats).map { WheelItem(title: $0.title, target: $0, action: nil) }
            }
            if files.allSatisfy({ FileFormat.detect(url: $0).kind == .video }) {
                return videoConverter.supportedTargets(for: files, candidates: formats).map { WheelItem(title: $0.title, target: $0, action: nil) }
            }
            if files.allSatisfy({ FileFormat.detect(url: $0).kind == .subtitle }) {
                return subtitleConverter.supportedTargets(for: files, candidates: formats).map { WheelItem(title: $0.title, target: $0, action: nil) }
            }
            if files.allSatisfy({ FileFormat.detect(url: $0).kind == .archive }) {
                return archiveConverter.supportedTargets(for: files, candidates: formats).map { WheelItem(title: $0.title, target: $0, action: nil) }
            }
            return converter.supportedTargets(for: files, candidates: formats).map { WheelItem(title: $0.title, target: $0, action: nil) }
        case .tools:
            return []
        case .actions:
            return [
                WheelItem(title: "Salin", target: nil, action: .copy),
                WheelItem(title: "Salin Jalur", target: nil, action: .copyPath),
                WheelItem(title: "Terminal", target: nil, action: .terminal),
                WheelItem(title: "AirDrop", target: nil, action: .airDrop)
            ]
        }
    }

    func radialOverlay(_ overlay: RadialOverlay, didDrop files: [URL], item: WheelItem, mode: WheelMode) {
        switch mode {
        case .convert:
            guard let target = item.target else { return }
            if target == .pdf, files.count > 1, files.allSatisfy({ FileFormat.detect(url: $0).kind == .image }) {
                requestPDFMerge(files: files)
                return
            }
            let outputDirectory = UserDefaults.standard.string(forKey: "outputDirectory").map(URL.init(fileURLWithPath:))
            let multiPageOutput = MultiPageOutput(rawValue: UserDefaults.standard.string(forKey: "multiPageOutput") ?? "") ?? .folder
            let imageOptions = ImageConversionOptions(
                jpgQuality: UserDefaults.standard.object(forKey: "jpgQuality") as? Double ?? 0.92,
                heicQuality: UserDefaults.standard.object(forKey: "heicQuality") as? Double ?? 0.92,
                pdf: PDFMergeOptions(
                    pageSize: PDFMergeOptions.PageSize(rawValue: UserDefaults.standard.string(forKey: "mergePDF.pageSize") ?? "") ?? .a4,
                    margin: PDFMergeOptions.Margin(rawValue: UserDefaults.standard.string(forKey: "mergePDF.margin") ?? "") ?? .none,
                    quality: PDFMergeOptions.Quality(rawValue: UserDefaults.standard.string(forKey: "mergePDF.quality") ?? "") ?? .balanced
                )
            )
            let id = runner.submit(inputs: files, target: target, outputDirectory: outputDirectory, multiPageOutput: multiPageOutput, processor: { [converter] input, target, temp, progress, cancelled in
                if FileFormat.detect(url: input).kind == .audio {
                    return try AudioConverter().convert(input: input, target: target, temporaryDirectory: temp.appendingPathComponent(UUID().uuidString), progress: progress, isCancelled: cancelled)
                }
                if FileFormat.detect(url: input).kind == .video {
                    return try VideoConverter().convert(input: input, target: target, temporaryDirectory: temp.appendingPathComponent(UUID().uuidString), progress: progress, isCancelled: cancelled)
                }
                if FileFormat.detect(url: input).kind == .subtitle {
                    return try SubtitleConverter().convert(input: input, target: target, temporaryDirectory: temp.appendingPathComponent(UUID().uuidString), progress: progress, isCancelled: cancelled)
                }
                if FileFormat.detect(url: input).kind == .archive {
                    return try ArchiveConverter().convert(input: input, target: target, temporaryDirectory: temp.appendingPathComponent(UUID().uuidString), progress: progress, isCancelled: cancelled)
                }
                return try converter.convert(input: input, target: target, temporaryDirectory: temp.appendingPathComponent(UUID().uuidString), progress: progress, isCancelled: cancelled, options: imageOptions)
            }) { [weak self] snapshot in
                self?.handle(snapshot: snapshot)
            }
            let progressWindow = ProgressWindowController()
            progressWindows[id] = progressWindow
            progressWindow.show(jobID: id, cancel: { [weak self] id in self?.runner.cancel(id: id) })
            log("Job \(id.uuidString) submitted: \(target.title) for \(files.count) file(s)")
        case .tools:
            showError("Tool ini akan tersedia pada fase berikutnya.")
        case .actions:
            perform(action: item.action, files: files)
        }
    }

    private func requestPDFMerge(files: [URL]) {
        let askEveryTime = UserDefaults.standard.object(forKey: "mergePDF.askEveryTime") as? Bool ?? true
        let orderedFiles = ImageSorting.sorted(files, by: .nameAscending)
        if !askEveryTime {
            let options = storedPDFOptions()
            let mode = PDFMergeMode(rawValue: UserDefaults.standard.string(forKey: "mergePDF.mode") ?? "") ?? .single
            submitPDFMerge(files: orderedFiles, mode: mode, options: options, outputName: "Gabungan")
            return
        }
        let controller = PDFMergeWindowController(files: orderedFiles) { [weak self] model in
            self?.submitPDFMerge(files: model.list.items, mode: model.mode, options: model.options, outputName: model.outputName, remember: model.rememberChoice)
        }
        pdfMergeWindow = controller
        controller.show(at: NSEvent.mouseLocation)
    }

    private func submitPDFMerge(files: [URL], mode: PDFMergeMode, options: PDFMergeOptions, outputName: String, remember: Bool = false) {
        guard !files.isEmpty else { return }
        if remember {
            UserDefaults.standard.set(false, forKey: "mergePDF.askEveryTime")
            UserDefaults.standard.set(mode.rawValue, forKey: "mergePDF.mode")
            UserDefaults.standard.set(options.pageSize.rawValue, forKey: "mergePDF.pageSize")
            UserDefaults.standard.set(options.margin.rawValue, forKey: "mergePDF.margin")
            UserDefaults.standard.set(options.quality.rawValue, forKey: "mergePDF.quality")
        }
        pdfMergeWindow?.close()
        pdfMergeWindow = nil
        let outputDirectory = UserDefaults.standard.string(forKey: "outputDirectory").map(URL.init(fileURLWithPath:))
        switch mode {
        case .single:
            let cleanName = outputName.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = runner.submitMerge(inputsInOrder: files, options: options, outputName: cleanName.isEmpty ? "Gabungan" : cleanName, outputDirectory: outputDirectory, processor: { inputs, temporaryFile, mergeOptions, progress, cancelled in
                try PDFBuilder.build(images: inputs, outputURL: temporaryFile, options: mergeOptions, progress: progress, isCancelled: cancelled)
                return temporaryFile
            }) { [weak self] snapshot in
                self?.handle(snapshot: snapshot)
            }
            let progressWindow = ProgressWindowController()
            progressWindows[id] = progressWindow
            progressWindow.show(jobID: id, cancel: { [weak self] id in self?.runner.cancel(id: id) })
            log("Job \(id.uuidString) submitted: gabungkan \(files.count) gambar menjadi PDF")
        case .each:
            let imageOptions = ImageConversionOptions(
                jpgQuality: UserDefaults.standard.object(forKey: "jpgQuality") as? Double ?? 0.92,
                heicQuality: UserDefaults.standard.object(forKey: "heicQuality") as? Double ?? 0.92,
                pdf: options
            )
            let id = runner.submit(inputs: files, target: .pdf, outputDirectory: outputDirectory, processor: { [converter] input, target, temp, progress, cancelled in
                try converter.convert(input: input, target: target, temporaryDirectory: temp.appendingPathComponent(UUID().uuidString), progress: progress, isCancelled: cancelled, options: imageOptions)
            }) { [weak self] snapshot in
                self?.handle(snapshot: snapshot)
            }
            let progressWindow = ProgressWindowController()
            progressWindows[id] = progressWindow
            progressWindow.show(jobID: id, cancel: { [weak self] id in self?.runner.cancel(id: id) })
            log("Job \(id.uuidString) submitted: \(files.count) gambar menjadi PDF terpisah")
        }
    }

    private func storedPDFOptions() -> PDFMergeOptions {
        PDFMergeOptions(
            pageSize: PDFMergeOptions.PageSize(rawValue: UserDefaults.standard.string(forKey: "mergePDF.pageSize") ?? "") ?? .a4,
            margin: PDFMergeOptions.Margin(rawValue: UserDefaults.standard.string(forKey: "mergePDF.margin") ?? "") ?? .none,
            quality: PDFMergeOptions.Quality(rawValue: UserDefaults.standard.string(forKey: "mergePDF.quality") ?? "") ?? .balanced
        )
    }

    private func handle(snapshot: JobSnapshot) {
        progressWindows[snapshot.id]?.update(snapshot)
        for failure in snapshot.failures {
            log("Job \(snapshot.id.uuidString) gagal untuk \(failure.input.lastPathComponent): \(failure.message)")
        }
        if snapshot.state == .failed { showError(snapshot.message) }
        if snapshot.state == .completed, !snapshot.failures.isEmpty {
            let details = snapshot.failures.map { "\($0.input.lastPathComponent): \($0.message)" }.joined(separator: "\n")
            showError("Selesai dengan \(snapshot.failures.count) file gagal.\n\n\(details)")
        }
        if snapshot.state == .completed, !snapshot.outputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(snapshot.outputs) }
        if snapshot.state == .completed || snapshot.state == .failed || snapshot.state == .cancelled {
            progressWindows.removeValue(forKey: snapshot.id)
        }
    }

    func radialOverlayDidCancel(_ overlay: RadialOverlay) {
        activeFiles.removeAll()
    }

    private func perform(action: WheelAction?, files: [URL]) {
        guard let action else { return }
        switch action {
        case .copy:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(files as [NSURL])
        case .copyPath:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(files.map(\.path).joined(separator: "\n"), forType: .string)
        case .terminal:
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            var seen = Set<URL>()
            let folders = files.map { $0.deletingLastPathComponent() }.filter { seen.insert($0).inserted }
            NSWorkspace.shared.open(folders, withApplicationAt: terminal, configuration: configuration)
        case .airDrop:
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: files) else {
                showError("AirDrop tidak tersedia untuk file yang dipilih.")
                return
            }
            service.perform(withItems: files)
        case .move, .float:
            showError("Aksi ini belum diaktifkan pada MVP.")
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.window?.hidesOnDeactivate = false
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func showLogs() {
        NSWorkspace.shared.open(logURL)
    }

    @objc private func quit() {
        guard runner.hasActiveJobs else {
            NSApp.terminate(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Konversi masih berjalan"
        alert.informativeText = "Yakin ingin keluar? Pekerjaan yang sedang berjalan akan dibatalkan."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keluar")
        alert.addButton(withTitle: "Batal")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runner.cancelAll()
        NSApp.terminate(nil)
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

    private func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8), let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: logURL, options: .atomic)
        }
    }

    private func cleanupOldTemporaryDirectories() {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        guard let urls = try? fileManager.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for url in urls where url.lastPathComponent.hasPrefix("Ceyloro-") {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate,
                  date < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func rotateLogIfNeeded() {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 1_048_576 else { return }
        let rotated = logURL.deletingLastPathComponent().appendingPathComponent("app.log.1")
        try? fileManager.removeItem(at: rotated)
        try? fileManager.moveItem(at: logURL, to: rotated)
    }
}
