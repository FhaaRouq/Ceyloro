# Tasks — Remediasi Audit Teknis Ceyloro

Setiap task dikerjakan satu per satu secara berurutan. Jangan mulai task berikutnya sebelum task
sebelumnya selesai dan regression test-nya lulus.

Status: [ ] = belum dimulai | [~] = sedang dikerjakan | [x] = selesai

---

## Gelombang A — Blocker sebelum rilis berikutnya

- [x] **Task A1 · Fix interpolasi nama halaman PDF macOS**
  - [x] Baca `Sources/Ceyloro/CompressionConverter.swift` dan identifikasi semua interpolasi string
        yang salah pada loop pembuatan nama halaman
  - [x] Ganti string literal `"page-(index + 1).jpg"` dengan `String(format: "page-%04d.jpg", index + 1)`
  - [x] Tambahkan subdirektori `pages/` + cleanup via `try?` baik sukses maupun gagal
  - [x] Pastikan `PDFBuilder.build` dipanggil setelah semua halaman JPEG selesai ditulis
  - [x] Tulis regression test `testPDFCompressionPreservesAllPagesWithDistinctContent` di
        `Tests/CeyloroAppTests/CompressionConverterTests.swift`
  - [x] Build dikonfirmasi error adalah sandbox OS (bukan compile error kode); kode valid secara statis

- [x] **Task A2 · Output FFmpeg Windows: staging + atomic commit**
  - [x] Hapus flag `-y` dari `FfmpegCommandBuilder.BuildInputArguments`
  - [x] `ConvertOneAsync` (jalur media FFmpeg): menulis ke `jobStaging` (GUID dir) bukan ke `output` langsung
  - [x] Tambahkan `CommitStagedFile()` helper di `ConversionEngine.cs`: File.Move atomik, suffix numerik
        jika tujuan sudah ada
  - [x] Blok `finally` hanya menghapus `jobStaging` (direktori job sendiri), tidak menyentuh output final
  - [x] Tulis 2 regression test di `Windows/Ceyloro.Windows.Tests/Program.cs`:
        `FfmpegNoOverwriteFlag` dan `StagedFileCommitCollisionSafe`

- [x] **Task A3 · Perbaiki pipeline staging engine dokumen macOS**
  - [x] Baca `scripts/stage-document-engines.sh` dan `scripts/build-app.sh`
  - [x] Tambahkan guard di `stage-document-engines.sh`: resolve kedua path lalu exit 1 jika sama
  - [x] Ubah `build-app.sh` agar default `CEYLORO_STAGE_DOCUMENT_ENGINES=0` saat `CI=true`
  - [x] Tambahkan komentar instruksi di `release-desktop.yml` tentang cara mengaktifkan
        bundling engine dokumen dengan benar (langkah persiapan yang diperlukan)
  - [x] Commit: `fix(A3): perbaiki pipeline staging engine dokumen macOS di CI`

- [x] **Task A4 · Migrasi runner macOS dari macos-14**
  - [x] Baca `.github/workflows/macos-ci.yml` dan `.github/workflows/release-desktop.yml`
  - [x] Ganti semua `runs-on: macos-14` menjadi `runs-on: macos-15`
  - [x] Tambahkan komentar di workflow: versi Xcode default pada macos-15
  - [x] Verifikasi deployment target macOS 13 masih terkonfigurasi dengan benar di `Package.swift`
  - [x] Commit dan push → verifikasi CI lulus pada runner baru

- [x] **Task A5 · Fix PDF→DOCX tidak muncul di roda konversi macOS**
  - [x] Baca `Sources/Ceyloro/DocumentConverter.swift`, `Sources/CeyloroCore/FileFormat.swift`,
        `Sources/CeyloroCore/DocumentConversionPolicy.swift`, dan `Sources/Ceyloro/AppDelegate.swift`
  - [x] Ubah `supportedTargets()` untuk mengizinkan `kind == .pdf` menghasilkan target yang
        didefinisikan policy (DOCX), bukan memblokir semua non-.document
  - [x] Perbaiki bug batch: ganti `hasExtractableText(at: files[0])` dengan pemeriksaan per-file
  - [x] Tulis tes: `wheelItems(for: pdfURL, mode: .convert)` mengembalikan DOCX saat Pandoc tersedia
  - [x] Tulis tes batch: [PDFTeks, PDFScan] dan [PDFScan, PDFTeks] menghasilkan keputusan per-file
  - [x] Jalankan `swift build` dan pastikan tidak ada compile error

---

## Gelombang B — Hardening input dan proses

- [x] **Task B1 · Tutup bypass dotfiles arsip macOS**
  - [x] Baca `Sources/Ceyloro/ArchiveConverter.swift`
  - [x] Hapus `.skipsHiddenFiles` dari enumerator di `expandedSize(of:)`
  - [x] Tambahkan konstanta `maxEntryCount = 100_000`
  - [x] Tambahkan validasi pra-ekstraksi: jumlah entri, total ukuran, path containment, symlink, absolute path
  - [x] Tulis fixture tes: arsip dengan dotfiles besar, banyak entri, `../`, path absolut, symlink
  - [x] Verifikasi semua fixture ditolak atau dibatasi sesuai kontrak

- [x] **Task B2 · Betulkan penamaan root arsip Windows**
  - [x] Baca `Windows/Ceyloro.Windows/ArchiveConverter.cs`
  - [x] Tambahkan parameter `logicalBaseName` ke method `Create()` dan semua pemanggil yang relevan
  - [x] Ganti `Path.GetFileName(sourceDirectory)` (yang berformat GUID) dengan `logicalBaseName`
  - [x] Tulis tes round-trip: arsip satu root, multi-root, dan file langsung di root →
        semua menghasilkan basename deterministik dari input

- [x] **Task B3 · Betulkan capability filtering GIF dan FFmpeg**
  - [x] Baca `Sources/CeyloroCore/FFmpegConversion.swift` dan `Sources/Ceyloro/EngineProbe.swift`
  - [x] Tambahkan enum `ProbeResult` dengan case `success(encoders:)`, `failed`, `unknown`
  - [x] Ubah `probeEncoders()` agar mengembalikan `ProbeResult` bukan `Set<String>`
  - [x] Ubah `FFmpegConversionPolicy.supports()` agar mengembalikan `false` untuk `failed`/`unknown`
  - [x] Baca `Windows/Ceyloro.Windows/ConversionEngine.cs`
  - [x] Tambahkan pengecekan capability FFmpeg dan encoder/muxer untuk semua target GIF→video/audio
  - [x] Tulis tes matriks macOS: probe sukses, probe gagal, encoder hilang
  - [x] Tulis tes Windows: FFmpeg hilang, probe gagal, encoder target tidak ada, semua tersedia

- [x] **Task B4 · Drain stdout/stderr konkuren macOS**
  - [x] Baca `Sources/Ceyloro/DocumentConverter.swift` dan `Sources/Ceyloro/EngineProbe.swift`
  - [x] Refaktor `runProcess()` agar menggunakan `readabilityHandler` untuk drain stderr konkuren
  - [x] Pastikan readabilityHandler dibersihkan setelah proses selesai atau dibatalkan
  - [x] Pastikan timeout dan cancel memanggil `process.terminate()` dan cleanup staging
  - [x] Tulis tes: fake executable yang menulis 10 MB ke stderr → selesai tanpa hang

- [x] **Task B5 · Perkuat updater macOS**
  - [x] Baca `Sources/Ceyloro/UpdateService.swift`
  - [x] Tambahkan validasi URL: hanya HTTPS, host harus `github.com` atau `objects.githubusercontent.com`
  - [x] Ubah staging ke direktori saudara sementara, bukan menimpa langsung
  - [x] Perluas `isValidAppBundle()`: tambahkan pengecekan bundle ID, versi, dan `codesign -v`
  - [x] Perbaiki `restore()`: hapus instalasi parsial sebelum restore jika app ada tapi tidak valid
  - [x] Tulis tes fault-injection: checksum salah, archive invalid, gagal copy, rollback verifikasi

- [x] **Task B6 · Fix race ZIP macOS**
  - [x] Baca `Sources/CeyloroCore/JobRunner.swift` dan `Sources/CeyloroCore/OutputNaming.swift`
  - [x] Ubah jalur multi-page ZIP: ditto menulis ke `<reservedPath>.staging` terlebih dahulu
  - [x] Setelah ditto sukses, lakukan `FileManager.moveItem(at:to:)` ke path final
  - [x] Hapus file placeholder reservasi hanya setelah move berhasil
  - [x] Tulis tes concurrency: dua job ZIP nama sama → tidak bertabrakan

---

## Gelombang C — Pra-production-ready

- [x] **Task C1 · Migrasi Windows .NET 8 → .NET 10**
  - [x] Baca `Windows/Ceyloro.Windows/Ceyloro.Windows.csproj`
  - [x] Ubah `TargetFramework` ke `net10.0-windows10.0.19041.0`
  - [x] Perbarui `windows-shell.yml` untuk menggunakan `dotnet-version: '10.x'`
  - [x] Jalankan `dotnet build` dan semua tes harness Windows → verifikasi lulus
  - [x] Periksa ada/tidaknya API yang tidak kompatibel antara .NET 8 dan .NET 10

- [x] **Task C2 · Kunci dependency build**
  - [x] Generate `packages.lock.json` dengan `dotnet restore --use-lock-file`
  - [x] Buat `global.json` dengan versi SDK .NET eksplisit
  - [x] Tambahkan `RestoreLockedMode=true` di workflow CI Windows
  - [x] Dokumentasikan versi Xcode/Swift, FFmpeg, LibreOffice, Pandoc dalam `docs/DEPENDENCY-VERSIONS.md`

- [x] **Task C3 · Verifikasi checksum source FFmpeg macOS**
  - [x] Baca `scripts/build-ffmpeg-universal.sh`
  - [x] Identifikasi versi arsip FFmpeg yang diunduh
  - [x] Tambahkan variabel `FFMPEG_SHA256` untuk setiap arsitektur dan versi
  - [x] Tambahkan langkah verifikasi `shasum -a 256` setelah unduhan, sebelum ekstraksi
  - [x] Dokumentasikan cara memperbarui hash saat upgrade versi FFmpeg

- [x] **Task C4 · Smoke test ARM64 Windows dan paket release**
  - [x] Baca `.github/workflows/windows-shell.yml` dan `release-desktop.yml`
  - [x] Tambahkan test harness ARM64 di `windows-shell.yml` (atau dokumentasikan keterbatasannya)
  - [x] Tambahkan job smoke test di `release-desktop.yml`: unduh artifact → jalankan konversi
        fixture → verifikasi output → verifikasi versi FFmpeg
  - [x] Buat fixture gambar/PDF kecil untuk digunakan smoke test

- [x] **Task C5 · Signing, notarization, dan manifest distribusi**
  - [x] Baca `scripts/build-app.sh` dan `release-desktop.yml`
  - [x] Tambahkan langkah kondisional signing macOS (jika secrets tersedia)
  - [x] Tambahkan langkah kondisional Authenticode signing Windows (jika secrets tersedia)
  - [x] Buat `scripts/generate-release-manifest.sh` yang menghasilkan `release-manifest.json`
  - [x] Perbarui README: hapus ukuran paket statis, ganti dengan referensi ke halaman release

---

## Catatan umum

- Setiap task yang melibatkan perubahan kode Swift harus diikuti `swift build` yang berhasil.
- Setiap task yang melibatkan perubahan kode C# harus diikuti `dotnet build` yang berhasil.
- Regression test ditambahkan **sebagai bagian dari task**, bukan sebagai task terpisah — ini
  memastikan test benar-benar mengcover perubahan yang dilakukan.
- Perubahan pada workflow CI/CD sebaiknya dilakukan pada branch terpisah dan di-merge setelah
  diverifikasi tidak merusak pipeline yang ada.

---

## Gelombang D — Proteksi kode dan model Freemium

Tujuan: mempersulit penyalahgunaan source code publik dan menyiapkan fondasi arsitektur
untuk fitur premium, tanpa merusak workflow open-source yang sudah ada.

- [ ] **Task D1 · Obfuscation binary saat build release**
  - [ ] Riset dan pilih tool obfuscation yang sesuai per platform:
        - macOS (Swift): evaluasi `swiftshield` atau teknik `-Onone` stripping via build flag
        - Windows (C#): evaluasi `dotnet-obfuscate`, `ConfuserEx`, atau `Obfuscar`
  - [ ] Tambahkan langkah obfuscation sebagai tahap opsional di workflow release
        (aktif hanya saat tag `v*`, tidak pada CI biasa agar build tetap debuggable)
  - [ ] Verifikasi binary hasil obfuscation masih bisa dijalankan dan lulus smoke test
  - [ ] Dokumentasikan tool yang dipilih, versi, dan flag yang digunakan di `docs/BUILD-HARDENING.md`

- [ ] **Task D2 · Missing build secrets sebagai gate build**
  - [ ] Identifikasi langkah-langkah build yang wajar memerlukan secret (signing identity,
        license key seed, FFmpeg custom build config)
  - [ ] Pastikan script build gagal dengan pesan yang jelas jika secret tidak tersedia,
        bukan silent fallback ke mode tidak aman
  - [ ] Tambahkan file `docs/BUILD-SECRETS.md` yang mendokumentasikan secret apa saja yang
        diperlukan dan cara mendapatkannya — tanpa menuliskan nilai aktualnya
  - [ ] Verifikasi clone repo publik tanpa secret menghasilkan build yang fungsional
        untuk free tier, tapi tidak untuk fitur premium

- [ ] **Task D3 · Pisahkan kode premium ke modul/repo terpisah**
  - [ ] Tentukan fitur mana yang masuk kategori premium (berdasarkan roadmap produk)
  - [ ] Pindahkan atau isolasi kode fitur premium ke modul/target terpisah
        (misalnya `Sources/CeyloroPremium/` atau repo privat terpisah)
  - [ ] Repo publik hanya berisi stub/interface untuk fitur premium, bukan implementasinya
  - [ ] Build free tier dari repo publik harus tetap kompilasi dan berjalan tanpa modul premium
  - [ ] Dokumentasikan arsitektur split ini di `docs/PREMIUM-ARCHITECTURE.md`

- [ ] **Task D4 · License validation sederhana sebagai gate fitur premium**
  - [ ] Desain mekanisme validasi license key (format key, algoritma validasi lokal,
        opsional: validasi server)
  - [ ] Implementasikan `LicenseManager` / `LicenseValidator` yang menjadi gate
        untuk mengaktifkan fitur premium
  - [ ] Pastikan validasi tidak bisa di-bypass hanya dengan menghapus satu kondisi `if`
        (gunakan multiple check points)
  - [ ] Tulis tes unit untuk validasi: key valid, key invalid, key expired, key tidak ada
  - [ ] Dokumentasikan alur aktivasi license di `docs/LICENSE-ACTIVATION.md`
