import AppKit
import ImageIO
import CeyloroCore
import SwiftUI

final class PDFMergeViewModel: ObservableObject {
    @Published var list: MergeListModel
    @Published var mode: PDFMergeMode = .single
    @Published var options: PDFMergeOptions
    @Published var outputName = "Gabungan"
    @Published var rememberChoice: Bool
    @Published var selection: Set<URL> = []
    @Published var thumbnails: [URL: NSImage] = [:]

    init(files: [URL]) {
        list = MergeListModel(items: ImageSorting.sorted(files, by: .nameAscending))
        mode = PDFMergeMode(rawValue: UserDefaults.standard.string(forKey: "mergePDF.mode") ?? "") ?? .single
        options = PDFMergeOptions(
            pageSize: PDFMergeOptions.PageSize(rawValue: UserDefaults.standard.string(forKey: "mergePDF.pageSize") ?? "") ?? .a4,
            margin: PDFMergeOptions.Margin(rawValue: UserDefaults.standard.string(forKey: "mergePDF.margin") ?? "") ?? .none,
            quality: PDFMergeOptions.Quality(rawValue: UserDefaults.standard.string(forKey: "mergePDF.quality") ?? "") ?? .balanced
        )
        let askEveryTime = UserDefaults.standard.object(forKey: "mergePDF.askEveryTime") as? Bool ?? true
        rememberChoice = !askEveryTime
    }

    private var thumbnailTask: Task<Void, Never>?

    func loadThumbnails() {
        thumbnailTask?.cancel()
        let urls = list.items
        thumbnailTask = Task.detached(priority: .userInitiated) { [weak self] in
            var loaded: [URL: NSImage] = [:]
            for url in urls {
                if Task.isCancelled { return }
                if let image = NSImage(contentsOf: url) {
                    loaded[url] = image
                }
            }
            if Task.isCancelled { return }
            DispatchQueue.main.async { [weak self] in
                self?.thumbnails = loaded
            }
        }
    }

    func cancelThumbnailLoading() {
        thumbnailTask?.cancel()
        thumbnailTask = nil
    }

    func move(from offsets: IndexSet, to destination: Int) {
        list.move(fromOffsets: offsets, toOffset: destination)
    }

    func remove(at offsets: IndexSet) {
        list.remove(at: offsets)
        selection = selection.filter { list.items.contains($0) }
    }

    func sort(by mode: ImageSortMode) {
        list.sort(by: mode)
    }

    func reverse() {
        list.reverse()
    }

    func moveSelection(up: Bool) {
        let indices = list.items.indices.filter { selection.contains(list.items[$0]) }
        guard !indices.isEmpty else { return }
        if up {
            guard let first = indices.first, first > 0 else { return }
            for index in indices {
                list.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
            }
        } else {
            guard let last = indices.last, last < list.items.count - 1 else { return }
            for index in indices.reversed() {
                list.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
            }
        }
    }

    func removeSelection() {
        remove(at: IndexSet(list.items.indices.filter { selection.contains(list.items[$0]) }))
    }
}

struct PDFMergeView: View {
    @ObservedObject var model: PDFMergeViewModel
    let onCancel: () -> Void
    let onCreate: (PDFMergeViewModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Buat PDF")
                .font(.title2.weight(.semibold))
            Picker("Mode", selection: $model.mode) {
                Text("Satu PDF gabungan").tag(PDFMergeMode.single)
                Text("Masing-masing jadi PDF").tag(PDFMergeMode.each)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Mode pembuatan PDF")

            HStack {
                Text("Urut cepat")
                Menu("Urutkan") {
                    Button("Nama A–Z") { model.sort(by: .nameAscending) }
                    Button("Nama Z–A") { model.sort(by: .nameDescending) }
                    Button("Tanggal dibuat") { model.sort(by: .createdAscending) }
                    Button("Tanggal diubah") { model.sort(by: .modifiedAscending) }
                    Button("Balik urutan") { model.reverse() }
                }
                .accessibilityLabel("Urutkan halaman")
                Spacer()
                Text("\(model.list.items.count) gambar")
                    .foregroundColor(.secondary)
            }

            List(selection: $model.selection) {
                ForEach(Array(model.list.items.enumerated()), id: \.element) { index, url in
                    HStack(spacing: 10) {
                        if let thumbnail = model.thumbnails[url] {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 42, height: 42)
                        } else {
                            Image(systemName: "photo")
                                .frame(width: 42, height: 42)
                                .foregroundColor(.secondary)
                        }
                        Text("\(index + 1)")
                            .frame(width: 24, alignment: .trailing)
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading) {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Text(Self.dimensions(for: url))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tag(url)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Halaman \(index + 1), \(url.lastPathComponent)")
                }
                .onMove(perform: model.move)
                .onDelete(perform: model.remove)
            }
            .listStyle(.inset)
            .disabled(model.mode == .each)
            .accessibilityLabel("Daftar halaman")
            .onMoveCommand { direction in
                switch direction {
                case .up: model.moveSelection(up: true)
                case .down: model.moveSelection(up: false)
                default: break
                }
            }
            .onDeleteCommand { model.removeSelection() }

            HStack {
                Picker("Ukuran halaman", selection: $model.options.pageSize) {
                    Text("A4").tag(PDFMergeOptions.PageSize.a4)
                    Text("Letter").tag(PDFMergeOptions.PageSize.letter)
                    Text("Sesuai gambar").tag(PDFMergeOptions.PageSize.matchImage)
                }
                .accessibilityLabel("Ukuran halaman")
                Picker("Margin", selection: $model.options.margin) {
                    Text("Tanpa").tag(PDFMergeOptions.Margin.none)
                    Text("Sedang").tag(PDFMergeOptions.Margin.medium)
                }
                .accessibilityLabel("Margin halaman")
                Picker("Kualitas", selection: $model.options.quality) {
                    Text("Asli").tag(PDFMergeOptions.Quality.original)
                    Text("Seimbang").tag(PDFMergeOptions.Quality.balanced)
                }
                .accessibilityLabel("Kualitas PDF")
            }

            if model.mode == .single {
                TextField("Nama file hasil", text: $model.outputName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Nama file hasil")
            }

            Toggle("Ingat pilihan saya dan jangan tanya lagi", isOn: $model.rememberChoice)
                .accessibilityLabel("Ingat pilihan dan jangan tanya lagi")
            HStack {
                Spacer()
                Button("Batal", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Buat PDF") { onCreate(model) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.list.items.isEmpty || (model.mode == .single && model.outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 560)
        .onAppear { model.loadThumbnails() }
    }

    private static func dimensions(for url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return "Dimensi tidak tersedia"
        }
        return "\(width) × \(height) px"
    }
}

final class PDFMergeWindowController: NSWindowController {
    private let model: PDFMergeViewModel
    private let onCreate: (PDFMergeViewModel) -> Void

    init(files: [URL], onCreate: @escaping (PDFMergeViewModel) -> Void) {
        model = PDFMergeViewModel(files: files)
        self.onCreate = onCreate
        let view = PDFMergeView(model: model, onCancel: {}, onCreate: { _ in })
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Buat PDF"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        super.init(window: window)
        let root = PDFMergeView(model: model, onCancel: { [weak self] in self?.cancel() }, onCreate: { [weak self] model in
            self?.onCreate(model)
        })
        hosting.rootView = root
        window.contentViewController = hosting
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func show(at point: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            let size = window?.frame.size ?? NSSize(width: 680, height: 560)
            let origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
            let x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
            let y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
            window?.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: false)
        } else {
            window?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func cancel() {
        model.cancelThumbnailLoading()
        close()
    }

    deinit {
        model.cancelThumbnailLoading()
    }
}
