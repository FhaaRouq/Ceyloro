import CryptoKit
import Foundation

struct CeyloroVersion: Comparable, Equatable, Sendable {
    let components: [Int]

    init(_ rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "", options: [.anchored])
        let numbers = normalized
            .split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
            .compactMap { Int($0) }
        components = numbers.isEmpty ? [0] : numbers
    }

    static func < (lhs: CeyloroVersion, rhs: CeyloroVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: CeyloroVersion, rhs: CeyloroVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    var displayValue: String {
        components.map(String.init).joined(separator: ".")
    }
}

struct CeyloroUpdateAsset: Decodable, Sendable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct CeyloroUpdateRelease: Decodable, Sendable {
    let tagName: String
    let name: String
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [CeyloroUpdateAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    var version: CeyloroVersion {
        CeyloroVersion(tagName)
    }

    var macOSAsset: CeyloroUpdateAsset? {
        assets.first { $0.name == "Ceyloro-macOS-universal.zip" }
    }

    var checksumAsset: CeyloroUpdateAsset? {
        assets.first { $0.name == "Ceyloro-macOS-universal.zip.sha256" }
    }
}

enum CeyloroUpdateError: LocalizedError {
    case invalidResponse
    case releaseMissingMacOSAsset
    case checksumMismatch
    case invalidArchive
    case destinationNotWritable
    case updaterLaunchFailed
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub tidak memberikan respons pembaruan yang valid."
        case .releaseMissingMacOSAsset:
            return "Paket macOS belum tersedia pada release terbaru."
        case .checksumMismatch:
            return "Checksum paket tidak cocok. Pembaruan dibatalkan demi keamanan."
        case .invalidArchive:
            return "Paket pembaruan tidak berisi aplikasi Ceyloro yang valid."
        case .destinationNotWritable:
            return "Folder aplikasi tidak dapat ditulis. Pindahkan Ceyloro ke folder yang dapat kamu ubah, lalu coba lagi."
        case .updaterLaunchFailed:
            return "Pembantu pembaruan tidak dapat dijalankan."
        case let .engineFailed(message):
            return "Mesin pembaruan gagal: \(message)"
        }
    }
}

final class CeyloroUpdateService {
    private let session: URLSession
    private let fileManager: FileManager
    private let repositoryURL = URL(string: "https://api.github.com/repos/Neural-Operations-Digital-Engineering/Ceyloro/releases/latest")

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    func latestRelease() async throws -> CeyloroUpdateRelease {
        guard let repositoryURL else { throw CeyloroUpdateError.invalidResponse }
        var request = URLRequest(url: repositoryURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ceyloro-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CeyloroUpdateError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CeyloroUpdateRelease.self, from: data)
    }

    func install(release: CeyloroUpdateRelease, currentAppURL: URL) async throws {
        guard let archiveAsset = release.macOSAsset else {
            throw CeyloroUpdateError.releaseMissingMacOSAsset
        }
        guard let checksumAsset = release.checksumAsset else {
            throw CeyloroUpdateError.checksumMismatch
        }
        let destinationFolder = currentAppURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: destinationFolder.path) else {
            throw CeyloroUpdateError.destinationNotWritable
        }

        let workDirectory = fileManager.temporaryDirectory.appendingPathComponent("CeyloroUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        do {
            let archiveURL = workDirectory.appendingPathComponent(archiveAsset.name)
            try await download(archiveAsset.browserDownloadURL, to: archiveURL)
            let checksumData = try await downloadData(checksumAsset.browserDownloadURL)
            guard let expectedChecksum = parseChecksum(checksumData),
                  try sha256(for: archiveURL) == expectedChecksum else {
                throw CeyloroUpdateError.checksumMismatch
            }

            let extractionDirectory = workDirectory.appendingPathComponent("extracted", isDirectory: true)
            try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
            try runDittoExtract(archiveURL: archiveURL, destination: extractionDirectory)
            let stagedApp = extractionDirectory.appendingPathComponent("Ceyloro.app", isDirectory: true)
            guard isValidAppBundle(stagedApp) else { throw CeyloroUpdateError.invalidArchive }
            try launchUpdater(currentAppURL: currentAppURL, stagedAppURL: stagedApp, workDirectory: workDirectory)
        } catch {
            try? fileManager.removeItem(at: workDirectory)
            throw error
        }
    }

    private func download(_ url: URL, to destination: URL) async throws {
        try validateDownloadURL(url)
        let (temporaryURL, response) = try await session.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CeyloroUpdateError.invalidResponse
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
    }

    private func downloadData(_ url: URL) async throws -> Data {
        try validateDownloadURL(url)
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CeyloroUpdateError.invalidResponse
        }
        return data
    }

    /// Validasi URL pembaruan: hanya HTTPS, host harus github.com atau objects.githubusercontent.com (B5).
    private func validateDownloadURL(_ url: URL) throws {
        guard url.scheme == "https" else {
            throw CeyloroUpdateError.engineFailed("URL pembaruan harus menggunakan HTTPS.")
        }
        guard let host = url.host?.lowercased(),
              host == "github.com" || host == "objects.githubusercontent.com" else {
            throw CeyloroUpdateError.engineFailed("Host URL pembaruan tidak diizinkan: \(host ?? "tidak diketahui")")
        }
    }

    private func parseChecksum(_ data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        guard let token = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).first,
              token.count == 64,
              token.allSatisfy(\.isHexDigit) else { return nil }
        return String(token).lowercased()
    }

    private func sha256(for url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func runDittoExtract(archiveURL: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CeyloroUpdateError.engineFailed("arsip ZIP tidak dapat diekstrak.")
        }
    }

    /// Validasi app bundle: executable, Info.plist, bundle ID, versi, dan codesign (B5).
    private func isValidAppBundle(_ appURL: URL) -> Bool {
        let executable = appURL.appendingPathComponent("Contents/MacOS/Ceyloro")
        let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
        guard fileManager.isExecutableFile(atPath: executable.path),
              fileManager.isReadableFile(atPath: infoPlist.path) else { return false }

        // Periksa bundle ID dan versi dari Info.plist
        guard let plist = NSDictionary(contentsOf: infoPlist),
              let bundleId = plist["CFBundleIdentifier"] as? String,
              bundleId == "com.node.Ceyloro",
              let version = plist["CFBundleShortVersionString"] as? String,
              !version.isEmpty else { return false }

        // Periksa codesign validitas (B5)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-v", appURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func launchUpdater(currentAppURL: URL, stagedAppURL: URL, workDirectory: URL) throws {
        let scriptURL = workDirectory.appendingPathComponent("apply-update.sh")
        let script = """
        #!/bin/sh
        set -eu
        current="$1"
        staged="$2"
        process_id="$3"
        root="$4"
        backup="${current}.update-backup-$$"
        new="${current}.ceyloro-new"
        restore() {
            # Hapus instalasi parsial sebelum restore jika app ada tapi tidak valid (B5)
            if [ -e "$current" ] && [ ! -f "$current/Contents/Info.plist" ]; then
                /bin/rm -rf "$current"
            fi
            if [ ! -e "$current" ] && [ -e "$backup" ]; then
                /bin/mv "$backup" "$current"
            fi
            /bin/rm -rf "$new" "$root" "$0"
            exit 1
        }
        while /bin/kill -0 "$process_id" 2>/dev/null; do
            /bin/sleep 1
        done
        # Salin staged app ke direktori saudara sementara, bukan langsung ke current (B5)
        # Jika ditto gagal, aplikasi saat ini tidak tersentuh.
        /usr/bin/ditto "$staged" "$new" || { /bin/rm -rf "$new"; exit 1; }
        # Swap: current → backup, new → current (rename atomik pada filesystem yang sama)
        /bin/mv "$current" "$backup" || restore
        /bin/mv "$new" "$current" || restore
        /usr/bin/open "$current"
        /bin/rm -rf "$backup" "$root" "$0"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            currentAppURL.path,
            stagedAppURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            workDirectory.path
        ]
        try process.run()
    }
}
