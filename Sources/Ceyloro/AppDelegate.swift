import AppKit
import CeyloroCore
import UserNotifications

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
    private let ffmpegConverter = FFmpegConverter()
    private var ffmpegURL: URL?
    private var ffmpegEncoders: Set<String> = []
    private let engineProbe = RuntimeEngineProbe()
    private var progressWindows: [UUID: ProgressWindowController] = [:]
    private var settingsWindow: SettingsWindowController?
    private var pdfMergeWindow: PDFMergeWindowController?
    private var activeFiles: [URL] = []
    private var currentMode: WheelMode = .convert
    private let logURL: URL = {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Ceyloro", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("app.log")
    }()
    private var logFileHandle: FileHandle?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        cleanupOldTemporaryDirectories()
        rotateLogIfNeeded()
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        requestNotificationPermission()
        checkPermissionsOnLaunch()
        overlay.overlayDelegate = self
        monitor.onWheelChange = { [weak self] files, point, flags in self?.showWheel(files: files, at: point, flags: flags) }
        monitor.onDiagnostic = { [weak self] message in self?.log("[DragMonitor] \(message)") }
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
        NotificationCenter.default.addObserver(forName: .ceyloroEngineSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshEngine()
        }
        refreshEngine()
        log("Ceyloro started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotKeyMonitor.stop()
        runner.cancelAll()
        cleanupOldTemporaryDirectories(cutoffInterval: 0)
        try? logFileHandle?.close()
        logFileHandle = nil
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = Bundle.main.image(forResource: "CeyloroMenuTemplate") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = image
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "circle.grid.3x3", accessibilityDescription: "Ceyloro")
        }
        statusItem.button?.imagePosition = .imageLeft
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

    private func updateStatusItemState() {
        let hasActiveJobs = !progressWindows.isEmpty
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem?.button else { return }
            if hasActiveJobs {
                button.title = " ●"
                button.toolTip = "Ceyloro (Mengonversi…)"
            } else {
                button.title = ""
                button.toolTip = "Ceyloro"
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendCompletionNotification(outputs: [URL]) {
        let content = UNMutableNotificationContent()
        content.title = "Konversi Selesai"
        if outputs.count == 1, let first = outputs.first {
            content.body = "Hasil disimpan: \(first.lastPathComponent)"
        } else {
            content.body = "\(outputs.count) file berhasil dikonversi."
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func refreshEngine() {
        let customPath = UserDefaults.standard.string(forKey: "ffmpegPath")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let engineStatus = self.engineProbe.inspect(customFFmpegPath: customPath)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.ffmpegURL = engineStatus.ffmpegURL
                self.ffmpegEncoders = engineStatus.encoders
                self.log("Engine AVFoundation: \(engineStatus.avFoundation ? "tersedia" : "tidak tersedia"); FFmpeg: \(engineStatus.ffmpegURL?.path ?? "tidak ditemukan") (encoders: \(engineStatus.encoders.count))")
            }
        }
    }

    private func showWheel(files: [URL], at point: NSPoint, flags: NSEvent.ModifierFlags) {
        activeFiles = files
        currentMode = flags.contains(.control) ? .actions : flags.contains(.option) ? .tools : .convert
        var items = wheelItems(for: files, mode: currentMode)
        if items.isEmpty {
            if currentMode == .tools {
                showToast("Tool tambahan belum tersedia pada versi ini.", systemImage: "sparkles")
                activeFiles.removeAll()
                return
            }
            if currentMode == .convert {
                let reason = conversionUnavailableReason(for: files)
                showError(reason)
                activeFiles.removeAll()
                return
            }
            currentMode = .actions
            items = wheelItems(for: files, mode: .actions)
        }
        guard !items.isEmpty else { return }
        overlay.present(files: files, mode: currentMode, items: items, at: point)
    }

    private func conversionUnavailableReason(for files: [URL]) -> String {
        guard !files.isEmpty else { return "Tidak ada file yang dipilih." }
        if files.contains(where: { !FileManager.default.isReadableFile(atPath: $0.path) }) {
            return "File tidak dapat dibaca atau izin file dibatasi."
        }
        let formats = files.map(FileFormat.detect(url:))
        if formats.contains(where: { $0.kind == .unknown }) {
            let unknownExts = formats.filter { $0.kind == .unknown }.map { ".\($0.fileExtension)" }.joined(separator: ", ")
            return "Format \(unknownExts) belum didukung untuk konversi."
        }
        if formats.contains(where: { $0.kind == .archive && !ArchiveConversionPolicy.nativeSources.contains($0.fileExtension) }) {
            let archiveExts = formats.filter { $0.kind == .archive && !ArchiveConversionPolicy.nativeSources.contains($0.fileExtension) }.map { ".\($0.fileExtension)" }.joined(separator: ", ")
            return "Format arsip \(archiveExts) hanya didukung baca/ekstrak, konversi native belum tersedia."
        }
        if formats.allSatisfy({ $0.kind == .audio || $0.kind == .video || $0.fileExtension == "gif" }) && ffmpegURL == nil {
            return "Format media ini memerlukan engine FFmpeg. Buka Pengaturan untuk memeriksa FFmpeg."
        }
        let common = matrix.commonTargets(for: formats)
        if common.isEmpty {
            return "Kombinasi jenis file yang dipilih tidak memiliki target konversi bersama."
        }
        return "Tidak ada target konversi yang tersedia untuk file ini."
    }

    private func checkPermissionsOnLaunch() {
        let isAccessibilityTrusted = HotKeyMonitor.isAccessibilityGranted
        log("Accessibility permission status: \(isAccessibilityTrusted ? "Granted" : "Not granted / Pending prompt")")
    }

    private func showWheelFromHotKey() {
        switch finderSelectionReader.readSelection() {
        case .success(let files):
            guard !files.isEmpty else {
                showToast("Pilih satu atau beberapa file di Finder terlebih dahulu.", systemImage: "hand.tap")
                return
            }
            showWheel(files: files, at: NSEvent.mouseLocation, flags: [.shift])
        case .noSelection:
            showToast("Pilih satu atau beberapa file di Finder terlebih dahulu.", systemImage: "hand.tap")
        case .permissionDenied(let reason):
            showPermissionAlert(
                title: "Izin Otomatisasi Diperlukan",
                message: "\(reason)\n\nBuka Pengaturan Sistem > Privasi & Keamanan > Otomatisasi, lalu izinkan Ceyloro mengontrol Finder.",
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
            )
        case .scriptError(let details):
            showError("Gagal membaca pilihan Finder: \(details)")
        }
    }

    private func showPermissionAlert(title: String, message: String, settingsURL: URL?) {
        log("[Permission] \(title): \(message)")
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        if let settingsURL {
            alert.addButton(withTitle: "Buka Pengaturan Sistem")
            alert.addButton(withTitle: "Tutup")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(settingsURL)
            }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func wheelItems(for files: [URL], mode: WheelMode) -> [WheelItem] {
        switch mode {
        case .convert:
            let detected = files.map(FileFormat.detect(url:))
            let formats = matrix.commonTargets(for: detected)
            if detected.allSatisfy({ $0.kind == .audio }) {
                let native = Set(audioConverter.supportedTargets(for: files, candidates: formats))
                let ffmpeg = Set(ffmpegConverter.supportedTargets(for: files, candidates: formats, ffmpegURL: ffmpegURL, encoders: ffmpegEncoders))
                return formats.filter { native.contains($0) || ffmpeg.contains($0) }.map { WheelItem(title: $0.title, target: $0, action: nil) }
            }
            if detected.allSatisfy({ $0.kind == .video }) {
                let native = Set(videoConverter.supportedTargets(for: files, candidates: formats))
                let ffmpeg = Set(ffmpegConverter.supportedTargets(for: files, candidates: formats, ffmpegURL: ffmpegURL, encoders: ffmpegEncoders))
                return formats.filter { native.contains($0) || ffmpeg.contains($0) }.map { WheelItem(title: $0.title, target: $0, action: nil) }
            }
            if detected.allSatisfy({ $0.fileExtension == "gif" }) {
                let hasAnimated = files.contains { ImageConverter.isAnimatedGIF(at: $0) }
                if hasAnimated {
                    let videoTargets = ffmpegConverter.supportedTargets(for: files, candidates: FFmpegConversionPolicy.videoTargets, ffmpegURL: ffmpegURL, encoders: ffmpegEncoders)
                    let imageTargets = converter.supportedTargets(for: files, candidates: [.png, .pdf])
                    return (videoTargets + imageTargets).map { WheelItem(title: $0.title, target: $0, action: nil) }
                } else {
                    return converter.supportedTargets(for: files, candidates: [.png, .jpg, .heic, .tiff, .pdf])
                        .map { WheelItem(title: $0.title, target: $0, action: nil) }
                }
            }
            if detected.allSatisfy({ $0.kind == .subtitle }) {
                return subtitleConverter.supportedTargets(for: files, candidates: formats).map { WheelItem(title: $0.title, target: $0, action: nil) }
            }
            if detected.allSatisfy({ $0.kind == .archive }) {
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
            let audioConverter = self.audioConverter
            let videoConverter = self.videoConverter
            let ffmpegConverter = self.ffmpegConverter
            let ffmpegURL = self.ffmpegURL
            let ffmpegEncoders = self.ffmpegEncoders
            let id = runner.submit(inputs: files, target: target, outputDirectory: outputDirectory, multiPageOutput: multiPageOutput, processor: { [converter, audioConverter, videoConverter, subtitleConverter, archiveConverter, ffmpegConverter, ffmpegURL, ffmpegEncoders] input, target, temp, progress, cancelled in
                let inputFormat = FileFormat.detect(url: input)
                if inputFormat.kind == .audio {
                    let audioTemp = temp.appendingPathComponent(UUID().uuidString)
                    if audioConverter.supportedTargets(for: [input], candidates: [target]).contains(target) {
                        return try audioConverter.convert(input: input, target: target, temporaryDirectory: audioTemp, progress: progress, isCancelled: cancelled)
                    }
                    return try ffmpegConverter.convert(input: input, target: target, temporaryDirectory: audioTemp, ffmpegURL: ffmpegURL, encoders: ffmpegEncoders, progress: progress, isCancelled: cancelled)
                }
                if inputFormat.kind == .video {
                    let videoTemp = temp.appendingPathComponent(UUID().uuidString)
                    if videoConverter.supportedTargets(for: [input], candidates: [target]).contains(target) {
                        return try videoConverter.convert(input: input, target: target, temporaryDirectory: videoTemp, progress: progress, isCancelled: cancelled)
                    }
                    return try ffmpegConverter.convert(input: input, target: target, temporaryDirectory: videoTemp, ffmpegURL: ffmpegURL, encoders: ffmpegEncoders, progress: progress, isCancelled: cancelled)
                }
                if inputFormat.fileExtension == "gif" {
                    if FFmpegConversionPolicy.videoTargets.contains(target) {
                        return try ffmpegConverter.convert(input: input, target: target, temporaryDirectory: temp.appendingPathComponent(UUID().uuidString), ffmpegURL: ffmpegURL, encoders: ffmpegEncoders, progress: progress, isCancelled: cancelled)
                    }
                    return try converter.convert(input: input, target: target, temporaryDirectory: temp.appendingPathComponent(UUID().uuidString), progress: progress, isCancelled: cancelled, options: imageOptions)
                }
                if inputFormat.kind == .subtitle {
                    return try subtitleConverter.convert(input: input, target: target, temporaryDirectory: temp.appendingPathComponent(UUID().uuidString), progress: progress, isCancelled: cancelled)
                }
                if inputFormat.kind == .archive {
                    return try archiveConverter.convert(input: input, target: target, temporaryDirectory: temp.appendingPathComponent(UUID().uuidString), progress: progress, isCancelled: cancelled)
                }
                return try converter.convert(input: input, target: target, temporaryDirectory: temp.appendingPathComponent(UUID().uuidString), progress: progress, isCancelled: cancelled, options: imageOptions)
            }) { [weak self] snapshot in
                self?.handle(snapshot: snapshot)
            }
            let progressWindow = ProgressWindowController()
            progressWindows[id] = progressWindow
            updateStatusItemState()
            progressWindow.show(jobID: id, cancel: { [weak self] id in self?.runner.cancel(id: id) })
            log("Job \(id.uuidString) submitted: \(target.title) for \(files.count) file(s)")
        case .tools:
            showToast("Tool ini akan tersedia pada fase berikutnya.", systemImage: "sparkles")
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
            updateStatusItemState()
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
            updateStatusItemState()
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
        if snapshot.state == .completed, !snapshot.outputs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(snapshot.outputs)
            sendCompletionNotification(outputs: snapshot.outputs)
        }
        if snapshot.state == .completed || snapshot.state == .failed || snapshot.state == .cancelled {
            progressWindows.removeValue(forKey: snapshot.id)
            updateStatusItemState()
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
                showToast("AirDrop tidak tersedia untuk file yang dipilih.", systemImage: "exclamationmark.triangle")
                return
            }
            service.perform(withItems: files)
        case .move, .float:
            showToast("Aksi ini belum diaktifkan pada MVP.", systemImage: "info.circle")
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

    private func showToast(_ message: String, systemImage: String = "info.circle") {
        ToastWindow.show(message: message, systemImage: systemImage)
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

    static func sanitizeLogMessage(_ message: String, homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String {
        guard !homeDirectory.isEmpty && homeDirectory != "/" else { return message }
        return message.replacingOccurrences(of: homeDirectory, with: "~")
    }

    private static let logDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private func log(_ message: String) {
        let sanitized = Self.sanitizeLogMessage(message)
        let line = "[\(Self.logDateFormatter.string(from: Date()))] \(sanitized)\n"
        guard let data = line.data(using: .utf8) else { return }

        if logFileHandle == nil {
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            logFileHandle = try? FileHandle(forWritingTo: logURL)
            _ = try? logFileHandle?.seekToEnd()
        }

        if let handle = logFileHandle {
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    private func cleanupOldTemporaryDirectories(cutoffInterval: TimeInterval = 24 * 60 * 60) {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        guard let urls = try? fileManager.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-cutoffInterval)
        for url in urls where url.lastPathComponent.hasPrefix("Ceyloro-") {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate,
                  date <= cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func rotateLogIfNeeded() {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 1_048_576 else { return }
        try? logFileHandle?.close()
        logFileHandle = nil
        let rotated = logURL.deletingLastPathComponent().appendingPathComponent("app.log.1")
        try? fileManager.removeItem(at: rotated)
        try? fileManager.moveItem(at: logURL, to: rotated)
    }
}
