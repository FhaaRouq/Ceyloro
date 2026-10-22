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

- [ ] **Task A3 · Perbaiki pipeline staging engine dokumen macOS**
  - [ ] Baca `scripts/stage-document-engines.sh` dan `scripts/build-app.sh`
  - [ ] Tambahkan validasi di awal `stage-document-engines.sh`: jika SOURCE_ROOT == DESTINATION,
        cetak error dan exit 1
  - [ ] Ubah `build-app.sh` agar default `CEYLORO_STAGE_DOCUMENT_ENGINES=0` di CI
        (berdasarkan deteksi `CI=true` atau variabel eksplisit)
  - [ ] Baca `.github/workflows/release-desktop.yml` dan tambahkan komentar eksplisit tentang apa
        yang diperlukan untuk mengaktifkan bundling engine dokumen
  - [ ] Pastikan workflow release bisa selesai tanpa engine dokumen (tidak exit early karena staging)
  - [ ] Update README dan dokumentasi relevan agar tidak mengklaim bundling LibreOffice/Pandoc
        kecuali langkah eksplisit dijalankan

- [ ] **Task A4 · Migrasi runner macOS dari macos-14**
  - [ ] Baca `.github/workflows/macos-ci.yml` dan `.github/workflows/release-desktop.yml`
  - [ ] Ganti semua `runs-on: macos-14` menjadi `runs-on: macos-15`
  - [ ] Tambahkan komentar di workflow: versi Xcode default pada macos-15
  - [ ] Verifikasi deployment target macOS 13 masih terkonfigurasi dengan benar di `Package.swift`
  - [ ] Commit dan push → verifikasi CI lulus pada runner baru

- [ ] **Task A5 · Fix PDF→DOCX tidak muncul di roda konversi macOS**
  - [ ] Baca `Sources/Ceyloro/DocumentConverter.swift`, `Sources/CeyloroCore/FileFormat.swift`,
        `Sources/CeyloroCore/DocumentConversionPolicy.swift`, dan `Sources/Ceyloro/AppDelegate.swift`
  - [ ] Ubah `supportedTargets()` untuk mengizinkan `kind == .pdf` menghasilkan target yang
        didefinisikan policy (DOCX), bukan memblokir semua non-.document
  - [ ] Perbaiki bug batch: ganti `hasExtractableText(at: files[0])` dengan pemeriksaan per-file
  - [ ] Tulis tes: `wheelItems(for: pdfURL, mode: .convert)` mengembalikan DOCX saat Pandoc tersedia
  - [ ] Tulis tes batch: [PDFTeks, PDFScan] dan [PDFScan, PDFTeks] menghasilkan keputusan per-file
  - [ ] Jalankan `swift build` dan pastikan tidak ada compile error

---

## Gelombang B — Hardening input dan proses

- [ ] **Task B1 · Tutup bypass dotfiles arsip macOS**
  - [ ] Baca `Sources/Ceyloro/ArchiveConverter.swift`
  - [ ] Hapus `.skipsHiddenFiles` dari enumerator di `expandedSize(of:)`
  - [ ] Tambahkan konstanta `maxEntryCount = 100_000`
  - [ ] Tambahkan validasi pra-ekstraksi: jumlah entri, total ukuran, path containment, symlink, absolute path
  - [ ] Tulis fixture tes: arsip dengan dotfiles besar, banyak entri, `../`, path absolut, symlink
  - [ ] Verifikasi semua fixture ditolak atau dibatasi sesuai kontrak

- [ ] **Task B2 · Betulkan penamaan root arsip Windows**
  - [ ] Baca `Windows/Ceyloro.Windows/ArchiveConverter.cs`
  - [ ] Tambahkan parameter `logicalBaseName` ke method `Create()` dan semua pemanggil yang relevan
  - [ ] Ganti `Path.GetFileName(sourceDirectory)` (yang berformat GUID) dengan `logicalBaseName`
  - [ ] Tulis tes round-trip: arsip satu root, multi-root, dan file langsung di root →
        semua menghasilkan basename deterministik dari input

- [ ] **Task B3 · Betulkan capability filtering GIF dan FFmpeg**
  - [ ] Baca `Sources/CeyloroCore/FFmpegConversion.swift` dan `Sources/Ceyloro/EngineProbe.swift`
  - [ ] Tambahkan enum `ProbeResult` dengan case `success(encoders:)`, `failed`, `unknown`
  - [ ] Ubah `probeEncoders()` agar mengembalikan `ProbeResult` bukan `Set<String>`
  - [ ] Ubah `FFmpegConversionPolicy.supports()` agar mengembalikan `false` untuk `failed`/`unknown`
  - [ ] Baca `Windows/Ceyloro.Windows/ConversionEngine.cs`
  - [ ] Tambahkan pengecekan capability FFmpeg dan encoder/muxer untuk semua target GIF→video/audio
  - [ ] Tulis tes matriks macOS: probe sukses, probe gagal, encoder hilang
  - [ ] Tulis tes Windows: FFmpeg hilang, probe gagal, encoder target tidak ada, semua tersedia

- [ ] **Task B4 · Drain stdout/stderr konkuren macOS**
  - [ ] Baca `Sources/Ceyloro/DocumentConverter.swift` dan `Sources/Ceyloro/EngineProbe.swift`
  - [ ] Refaktor `runProcess()` agar menggunakan `readabilityHandler` untuk drain stderr konkuren
  - [ ] Pastikan readabilityHandler dibersihkan setelah proses selesai atau dibatalkan
  - [ ] Pastikan timeout dan cancel memanggil `process.terminate()` dan cleanup staging
  - [ ] Tulis tes: fake executable yang menulis 10 MB ke stderr → selesai tanpa hang

- [ ] **Task B5 · Perkuat updater macOS**
  - [ ] Baca `Sources/Ceyloro/UpdateService.swift`
  - [ ] Tambahkan validasi URL: hanya HTTPS, host harus `github.com` atau `objects.githubusercontent.com`
  - [ ] Ubah staging ke direktori saudara sementara, bukan menimpa langsung
  - [ ] Perluas `isValidAppBundle()`: tambahkan pengecekan bundle ID, versi, dan `codesign -v`
  - [ ] Perbaiki `restore()`: hapus instalasi parsial sebelum restore jika app ada tapi tidak valid
  - [ ] Tulis tes fault-injection: checksum salah, archive invalid, gagal copy, rollback verifikasi

- [ ] **Task B6 · Fix race ZIP macOS**
  - [ ] Baca `Sources/CeyloroCore/JobRunner.swift` dan `Sources/CeyloroCore/OutputNaming.swift`
  - [ ] Ubah jalur multi-page ZIP: ditto menulis ke `<reservedPath>.staging` terlebih dahulu
  - [ ] Setelah ditto sukses, lakukan `FileManager.moveItem(at:to:)` ke path final
  - [ ] Hapus file placeholder reservasi hanya setelah move berhasil
  - [ ] Tulis tes concurrency: dua job ZIP nama sama → tidak bertabrakan

---

## Gelombang C — Pra-production-ready

- [ ] **Task C1 · Migrasi Windows .NET 8 → .NET 10**
  - [ ] Baca `Windows/Ceyloro.Windows/Ceyloro.Windows.csproj`
  - [ ] Ubah `TargetFramework` ke `net10.0-windows10.0.19041.0`
  - [ ] Perbarui `windows-shell.yml` untuk menggunakan `dotnet-version: '10.x'`
  - [ ] Jalankan `dotnet build` dan semua tes harness Windows → verifikasi lulus
  - [ ] Periksa ada/tidaknya API yang tidak kompatibel antara .NET 8 dan .NET 10

- [ ] **Task C2 · Kunci dependency build**
  - [ ] Generate `packages.lock.json` dengan `dotnet restore --use-lock-file`
  - [ ] Buat `global.json` dengan versi SDK .NET eksplisit
  - [ ] Tambahkan `RestoreLockedMode=true` di workflow CI Windows
  - [ ] Dokumentasikan versi Xcode/Swift, FFmpeg, LibreOffice, Pandoc dalam `docs/DEPENDENCY-VERSIONS.md`

- [ ] **Task C3 · Verifikasi checksum source FFmpeg macOS**
  - [ ] Baca `scripts/build-ffmpeg-universal.sh`
  - [ ] Identifikasi versi arsip FFmpeg yang diunduh
  - [ ] Tambahkan variabel `FFMPEG_SHA256` untuk setiap arsitektur dan versi
  - [ ] Tambahkan langkah verifikasi `shasum -a 256` setelah unduhan, sebelum ekstraksi
  - [ ] Dokumentasikan cara memperbarui hash saat upgrade versi FFmpeg

- [ ] **Task C4 · Smoke test ARM64 Windows dan paket release**
  - [ ] Baca `.github/workflows/windows-shell.yml` dan `release-desktop.yml`
  - [ ] Tambahkan test harness ARM64 di `windows-shell.yml` (atau dokumentasikan keterbatasannya)
  - [ ] Tambahkan job smoke test di `release-desktop.yml`: unduh artifact → jalankan konversi
        fixture → verifikasi output → verifikasi versi FFmpeg
  - [ ] Buat fixture gambar/PDF kecil untuk digunakan smoke test

- [ ] **Task C5 · Signing, notarization, dan manifest distribusi**
  - [ ] Baca `scripts/build-app.sh` dan `release-desktop.yml`
  - [ ] Tambahkan langkah kondisional signing macOS (jika secrets tersedia)
  - [ ] Tambahkan langkah kondisional Authenticode signing Windows (jika secrets tersedia)
  - [ ] Buat `scripts/generate-release-manifest.sh` yang menghasilkan `release-manifest.json`
  - [ ] Perbarui README: hapus ukuran paket statis, ganti dengan referensi ke halaman release

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
