# Design — Remediasi Audit Teknis Ceyloro

## Gambaran umum

Dokumen ini merinci pendekatan teknis untuk setiap item requirement. Setiap bagian menjelaskan
perubahan yang perlu dilakukan, pendekatan yang dipilih, dan trade-off yang relevan.

---

## Gelombang A

### A1 · Fix interpolasi nama halaman PDF macOS

**File yang diubah:** `Sources/Ceyloro/CompressionConverter.swift`

**Perubahan:**
```swift
// SEBELUM (bug):
let pageURL = temporaryDirectory.appendingPathComponent("page-(index + 1).jpg")

// SESUDAH (fix):
let pageURL = temporaryDirectory.appendingPathComponent("page-\(String(format: "%04d", index + 1)).jpg")
```

Gunakan zero-padding 4 digit agar urutan file konsisten saat disortir secara leksikografis (penting
untuk PDF dengan banyak halaman). Nama hasil: `page-0001.jpg`, `page-0002.jpg`, dst.

**Cleanup:** Tambahkan `defer` block yang menghapus seluruh `temporaryDirectory` setelah proses
selesai (sukses maupun gagal). Pastikan cleanup tidak terjadi sebelum `PDFBuilder.build` selesai.

**Tes regresi yang ditambahkan:**
- Buat PDF 3 halaman dengan warna solid berbeda (merah, hijau, biru) menggunakan `PDFKit`.
- Jalankan kompresi.
- Verifikasi PDF output: jumlah halaman = 3, warna dominan halaman pertama ≠ halaman ketiga.
- Tes harus **gagal** dengan implementasi lama sebelum fix diterapkan.

**Lokasi tes:** `Tests/CeyloroCoreTests/` atau `Tests/CeyloroAppTests/`

---

### A2 · Output FFmpeg Windows: staging + atomic commit

**File yang diubah:** `Windows/Ceyloro.Windows/ConversionEngine.cs`,
`Windows/Ceyloro.Windows/FfmpegCommandBuilder.cs`

**Pendekatan:**

1. Setiap job FFmpeg mendapat direktori staging unik berbasis `Guid.NewGuid()` di dalam temp folder
   sistem.
2. `FfmpegCommandBuilder` menulis output ke path staging, bukan path final.
3. Flag `-y` dihapus dari command builder (tidak boleh overwrite tanpa persetujuan).
4. Setelah FFmpeg exit code 0 dan file staging divalidasi (exists, size > 0), lakukan commit:

```csharp
// Commit atomik ke output final
string finalPath = UniqueOutputPath(desiredOutputPath);
File.Move(stagingPath, finalPath); // atomic pada volume yang sama di Windows
```

5. Blok `finally` hanya menghapus direktori staging job sendiri, tidak pernah menyentuh `finalPath`
   yang sudah berhasil di-commit.

**Perubahan `UniqueOutputPath`:** Fungsi ini tetap digunakan untuk mendapatkan nama kandidat, tetapi
pemanggilan dilakukan tepat sebelum `File.Move`, bukan saat job dimulai, sehingga jeda antara cek
dan commit diminimalkan.

**Catatan:** `File.Move` pada Windows bersifat atomik untuk file pada volume yang sama. Jika
staging dan output berbeda volume, gunakan copy + delete dengan validasi ukuran.

**Tes yang ditambahkan:**
- Dua job FFmpeg bersamaan (Task.WhenAll) dengan basename identik → keduanya menghasilkan file
  output berbeda dengan nama unik.
- Cancel satu job saat paralel berjalan → file output job yang sukses tidak tersentuh.

---

### A3 · Pipeline staging engine dokumen macOS

**File yang diubah:** `scripts/stage-document-engines.sh`, `scripts/build-app.sh`,
`.github/workflows/release-desktop.yml`

**Pendekatan yang dipilih: opsional dengan eksplisit**

Daripada memaksa bundling LibreOffice/Pandoc di setiap CI run (yang membutuhkan unduhan besar dan
kebergantungan pada ketersediaan CDN), pilihan yang lebih aman untuk saat ini adalah:

1. **Pisahkan SOURCE_ROOT dan DESTINATION** secara eksplisit di `stage-document-engines.sh`:
   ```bash
   if [ "$SOURCE_ROOT" = "$DESTINATION" ]; then
     echo "ERROR: SOURCE_ROOT dan DESTINATION tidak boleh sama: $SOURCE_ROOT" >&2
     exit 1
   fi
   ```

2. **Build CI default** (`CEYLORO_STAGE_DOCUMENT_ENGINES=0`) tidak memerlukan engine dokumen.
   Workflow release menggunakan opsi ini kecuali ada langkah eksplisit yang menyiapkannya.

3. **Tambahkan komentar eksplisit** di workflow release tentang apa yang perlu dilakukan untuk
   mengaktifkan bundling engine dokumen (manual step dengan instruksi lengkap).

4. Perbarui README dan dokumentasi agar akurat dengan status bundling.

**Tes verifikasi:** Workflow CI harus berhasil menyelesaikan build `.app` tanpa engine dokumen saat
`CEYLORO_STAGE_DOCUMENT_ENGINES=0`.

---

### A4 · Migrasi runner macOS

**File yang diubah:** `.github/workflows/macos-ci.yml`, `.github/workflows/release-desktop.yml`

**Perubahan:**
```yaml
# SEBELUM:
runs-on: macos-14

# SESUDAH:
runs-on: macos-15
```

**Verifikasi pasca-migrasi:**
- Toolchain Xcode yang digunakan dicatat di komentar workflow (versi Xcode default pada macos-15).
- Build universal (arm64 + x86_64) tetap menghasilkan binary yang valid.
- Deployment target macOS 13 tidak berubah.

**Risiko:** Xcode default pada macos-15 mungkin berbeda dari macos-14. Tambahkan langkah eksplisit
`xcode-select` jika diperlukan untuk menjamin versi.

---

### A5 · Fix PDF→DOCX di roda konversi macOS

**File yang diubah:** `Sources/Ceyloro/DocumentConverter.swift`,
`Sources/Ceyloro/AppDelegate.swift`

**Perubahan pada `supportedTargets()`:**

Ganti filter global `kind == .document` dengan filter berbasis policy:

```swift
// SEBELUM:
guard fileFormat.kind == .document else { return [] }

// SESUDAH:
// Izinkan .pdf untuk pasangan yang didukung policy
let allowedKinds: Set<FileFormat.Kind> = [.document, .pdf]
guard allowedKinds.contains(fileFormat.kind) else { return [] }
```

Kemudian saring target yang dikembalikan agar hanya mencakup target yang benar-benar didukung
policy untuk kind tersebut (PDF → [.docx] jika engine tersedia, Document → target lengkap).

**Perubahan pada pengecekan batch:**

```swift
// SEBELUM (bug — memakai files[0] untuk semua):
guard hasExtractableText(at: files[0]) else { ... }

// SESUDAH — periksa setiap file:
let eligibleFiles = files.filter { url in
    guard FileFormat.detect(url)?.kind == .pdf else { return true }
    return hasExtractableText(at: url)
}
guard !eligibleFiles.isEmpty else { return [] }
```

**Tes yang ditambahkan:**
- `wheelItems(for: pdfURL, mode: .convert)` mengembalikan DOCX saat Pandoc tersedia.
- Batch [PDFTeks, PDFScan] dan [PDFScan, PDFTeks] menghasilkan keputusan yang benar per-file.

---

## Gelombang B

### B1 · Bypass dotfiles arsip macOS

**File yang diubah:** `Sources/Ceyloro/ArchiveConverter.swift`

**Perubahan:**
```swift
// Hapus .skipsHiddenFiles dari enumerator:
let enumerator = FileManager.default.enumerator(
    at: directory,
    includingPropertiesForKeys: [.fileSizeKey],
    options: []  // ← bukan .skipsHiddenFiles
)
```

Tambahkan batas entri pra-ekstraksi:
```swift
static let maxEntryCount = 100_000
static let maxExpandedBytes: Int64 = 2_000_000_000

// Sebelum ekstraksi, enumerate entri arsip dan validasi:
guard entryCount <= maxEntryCount else { throw ArchiveError.tooManyEntries }
guard estimatedSize <= maxExpandedBytes else { throw ArchiveError.tooLarge }
// Validasi setiap path: tidak boleh mengandung "../", tidak boleh absolute, tidak boleh symlink
```

---

### B2 · Penamaan root arsip Windows

**File yang diubah:** `Windows/Ceyloro.Windows/ArchiveConverter.cs`

**Perubahan:** Pisahkan `logicalBaseName` (dari nama file input) dari `stagingDirectory` (GUID).
`Create()` menerima `logicalBaseName` sebagai parameter terpisah dan menggunakannya sebagai root
direktori di dalam arsip output, bukan `Path.GetFileName(stagingDirectory)`.

---

### B3 · Capability filtering GIF dan FFmpeg

**macOS — `FFmpegConversion.swift` dan `EngineProbe.swift`:**

Tambahkan enum status probe:
```swift
enum ProbeResult {
    case success(encoders: Set<String>)
    case failed
    case unknown
}
```

`FFmpegConversionPolicy.supports()` mengembalikan `false` untuk `failed` dan `unknown`, dan hanya
mengembalikan `true` untuk `success` jika encoder yang diperlukan ada.

**Windows — `ConversionEngine.cs`:**

Setiap target GIF→video/audio harus melewati pengecekan:
1. FFmpeg executable ditemukan dan valid.
2. Encoder/muxer yang diperlukan untuk target tersebut ada dalam daftar kapabilitas.

---

### B4 · Drain stdout/stderr konkuren macOS

**File yang diubah:** `Sources/Ceyloro/DocumentConverter.swift`, `Sources/Ceyloro/EngineProbe.swift`

**Pendekatan:** Gunakan `FileHandle.readabilityHandler` untuk drain pipe secara asinkron:

```swift
var stderrData = Data()
let stderrQueue = DispatchQueue(label: "stderr-drain")
process.standardError = stderrPipe

stderrPipe.fileHandleForReading.readabilityHandler = { handle in
    stderrQueue.async {
        stderrData.append(handle.availableData)
    }
}

process.launch()
process.waitUntilExit()
stderrPipe.fileHandleForReading.readabilityHandler = nil
```

Pastikan timeout dan pembatalan memanggil `process.terminate()` dan menghapus handler.

---

### B5 · Perkuat updater macOS

**File yang diubah:** `Sources/Ceyloro/UpdateService.swift`

**Perubahan kunci:**
1. Staging di `<AppPath>.update-staging/` (direktori saudara sementara).
2. Validasi URL sebelum request: hanya HTTPS, host harus `github.com` atau `objects.githubusercontent.com`.
3. `isValidAppBundle()` diperluas: periksa `CFBundleIdentifier`, versi, dan `codesign -v`.
4. `restore()` diperluas: jika path app ada tapi tidak valid (parsial), hapus dulu lalu restore.

---

### B6 · Fix race ZIP macOS

**File yang diubah:** `Sources/CeyloroCore/JobRunner.swift`

**Perubahan:** Alih-alih melepas reservasi sebelum `ditto`, jalankan `ditto` ke path staging unik
(`<reservedPath>.tmp`), lalu setelah sukses lakukan `FileManager.moveItem(at:to:)` ke path final.
Hapus reservasi placeholder hanya setelah move berhasil.

---

## Gelombang C

### C1 · Migrasi .NET 8 → .NET 10

**Perubahan di `.csproj`:**
```xml
<!-- SEBELUM -->
<TargetFramework>net8.0-windows10.0.19041.0</TargetFramework>

<!-- SESUDAH -->
<TargetFramework>net10.0-windows10.0.19041.0</TargetFramework>
```

Perbarui workflow CI untuk menggunakan `dotnet-version: '10.x'`.

---

### C2 · Kunci dependency

- Jalankan `dotnet restore --use-lock-file` untuk generate `packages.lock.json`.
- Tambahkan `global.json` dengan `sdk.version` eksplisit.
- Tambahkan `RestoreLockedMode` di CI: `dotnet restore --locked-mode`.

---

### C3 · Checksum FFmpeg macOS

Tambahkan variable di `build-ffmpeg-universal.sh`:
```bash
FFMPEG_ARM64_SHA256="<hash>"
FFMPEG_X86_SHA256="<hash>"
# ...verify setelah download
shasum -a 256 -c <<< "$FFMPEG_ARM64_SHA256  ffmpeg-arm64.tar.gz"
```

---

### C4 · Smoke test ARM64 + paket release

Tambahkan job baru di `release-desktop.yml` yang:
1. Mengunduh artifact yang baru dibangun.
2. Menjalankan konversi fixture gambar sederhana.
3. Verifikasi exit code dan keberadaan output.

---

### C5 · Signing dan manifest

Tambahkan langkah kondisional di workflow:
```yaml
- name: Sign and Notarize (if secrets available)
  if: env.APPLE_SIGNING_IDENTITY != ''
  run: |
    codesign --sign "$APPLE_SIGNING_IDENTITY" --deep --timestamp Ceyloro.app
    xcrun notarytool submit ...
    xcrun stapler staple Ceyloro.app
```

Buat script `scripts/generate-release-manifest.sh` yang menghasilkan `release-manifest.json`
dengan versi, arsitektur, dependency, dan status signing.

---

## Urutan file yang disentuh per gelombang

| Gelombang | File |
|-----------|------|
| A1 | `Sources/Ceyloro/CompressionConverter.swift`, tes baru |
| A2 | `Windows/Ceyloro.Windows/ConversionEngine.cs`, `FfmpegCommandBuilder.cs`, tes baru |
| A3 | `scripts/stage-document-engines.sh`, `scripts/build-app.sh`, `release-desktop.yml` |
| A4 | `macos-ci.yml`, `release-desktop.yml` |
| A5 | `Sources/Ceyloro/DocumentConverter.swift`, `AppDelegate.swift`, tes baru |
| B1 | `Sources/Ceyloro/ArchiveConverter.swift`, tes baru |
| B2 | `Windows/Ceyloro.Windows/ArchiveConverter.cs`, tes baru |
| B3 | `Sources/CeyloroCore/FFmpegConversion.swift`, `EngineProbe.swift`, `ConversionEngine.cs`, tes baru |
| B4 | `Sources/Ceyloro/DocumentConverter.swift`, `EngineProbe.swift` |
| B5 | `Sources/Ceyloro/UpdateService.swift`, tes baru |
| B6 | `Sources/CeyloroCore/JobRunner.swift`, tes baru |
| C1 | `Ceyloro.Windows.csproj`, `windows-shell.yml` |
| C2 | `packages.lock.json` (generate), `global.json` (baru) |
| C3 | `scripts/build-ffmpeg-universal.sh` |
| C4 | `release-desktop.yml` |
| C5 | `scripts/build-app.sh`, `release-desktop.yml`, `scripts/generate-release-manifest.sh` (baru) |
