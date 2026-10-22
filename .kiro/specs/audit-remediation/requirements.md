# Requirements — Remediasi Audit Teknis Ceyloro

## Latar belakang

Audit teknis tanggal 22 Oktober 2026 menemukan sejumlah masalah pada source code macOS Swift/AppKit
dan shell Windows C#/.NET. Temuan dibagi menjadi tiga prioritas: P1 (kritis), P2 (penting), dan P3
(kualitas/konsistensi). Spec ini mendefinisikan requirement untuk menutup semua temuan secara
terstruktur, gelombang demi gelombang, tanpa merusak fungsionalitas yang sudah berjalan.

Scope spec ini mencakup seluruh remediasi dari laporan audit — tidak termasuk fitur baru di luar
yang diperlukan untuk menutup temuan.

---

## Gelombang A — Blocker sebelum rilis berikutnya

### A1 · Perbaiki bug interpolasi nama halaman kompresi PDF macOS

**File:** `Sources/Ceyloro/CompressionConverter.swift` sekitar baris 62

**Masalah:** String literal `"page-(index + 1).jpg"` tidak mengandung interpolasi Swift yang benar
(`\(...)`), sehingga semua iterasi loop menulis ke nama file yang sama. PDF hasil berpotensi berisi
pengulangan halaman terakhir pada setiap halaman.

**Requirement:**
- R-A1.1: Nama file JPEG sementara per halaman harus unik (contoh: `page-\(index + 1).jpg` atau
  format serupa dengan zero-padding).
- R-A1.2: Semua file sementara (JPEG per halaman) harus dibersihkan baik saat sukses maupun gagal.
- R-A1.3: Harus ada regression test: buat PDF 3+ halaman dengan konten berbeda per halaman,
  kompres, verifikasi jumlah halaman tetap sama dan setiap halaman berbeda isinya.

---

### A2 · Output FFmpeg Windows harus collision-safe (staging + atomic commit)

**File:** `Windows/Ceyloro.Windows/ConversionEngine.cs` baris 328–330, 399–416, 469–484, 709–715;
`Windows/Ceyloro.Windows/FfmpegCommandBuilder.cs` baris 10–11

**Masalah:** `UniqueOutputPath()` hanya memeriksa keberadaan file tanpa mencadangkan jalur secara
eksklusif. FFmpeg menulis langsung ke tujuan final dengan flag `-y`, memungkinkan dua job bersamaan
dengan nama file sama saling menimpa outputnya.

**Requirement:**
- R-A2.1: Setiap job FFmpeg harus menulis ke direktori staging unik per job, bukan langsung ke
  path output final.
- R-A2.2: Setelah FFmpeg selesai dengan exit code sukses dan file divalidasi, lakukan commit ke
  output final menggunakan operasi atomik/eksklusif (tanpa flag `-y` ke path final).
- R-A2.3: Jika nama final sudah ada saat commit, gunakan mekanisme rename collision-safe (suffix
  numerik unik) — tidak boleh menimpa output job lain.
- R-A2.4: Cleanup di blok `finally` hanya boleh menghapus file sementara milik job sendiri, tidak
  pernah menyentuh output yang sudah dicommit oleh job lain.
- R-A2.5: Harus ada tes: dua job bersamaan dengan basename identik tidak pernah saling menimpa.
- R-A2.6: Harus ada tes: cancel satu job saat job paralel berjalan tidak menghapus output job lain.

---

### A3 · Perbaiki pipeline staging engine dokumen macOS di CI/CD

**File:** `.github/workflows/release-desktop.yml`; `scripts/build-app.sh`;
`scripts/stage-document-engines.sh`

**Masalah 1:** Workflow release tidak mengunduh/menyiapkan LibreOffice dan Pandoc sebelum
`build-app.sh` menjalankan staging, padahal staging wajib menemukannya — CI kemungkinan gagal
sebelum paket terbentuk.

**Masalah 2:** Jika `CEYLORO_DOCUMENT_ENGINES_PATH` diisi, variabel ini diteruskan sebagai source
sekaligus destination ke skrip staging, berisiko `cp -R` menyalin folder ke dirinya sendiri.

**Requirement:**
- R-A3.1: `SOURCE_ROOT` dan `DESTINATION` di `stage-document-engines.sh` harus selalu berupa path
  yang berbeda; skrip harus memvalidasi ini di awal dan keluar dengan error yang jelas jika sama.
- R-A3.2: Workflow release harus secara eksplisit menyiapkan (download/verify) LibreOffice dan
  Pandoc dengan versi yang dipin sebelum menjalankan `build-app.sh`, ATAU menonaktifkan staging
  wajib untuk build CI dan mendokumentasikan bahwa bundling engine dokumen adalah langkah opsional.
- R-A3.3: Jika opsi non-bundling dipilih (R-A3.2 opsional), semua klaim README dan dokumentasi
  tentang paket membawa LibreOffice/Pandoc harus diperbarui agar akurat.
- R-A3.4: CI sukses pada workflow release (dry-run atau mock) membuktikan paket `.app` terbentuk
  tanpa error staging.

---

### A4 · Migrasi runner macOS dari macos-14

**File:** `.github/workflows/macos-ci.yml` baris 14;
`.github/workflows/release-desktop.yml` baris 12

**Masalah:** Runner `macos-14` dijadwalkan retirement penuh 2 November 2026 (tinggal ~11 hari dari
tanggal audit). CI dan rilis bisa berhenti meski kode tidak berubah.

**Requirement:**
- R-A4.1: Kedua workflow harus dimigrasi ke image runner yang didukung (misalnya `macos-15`).
- R-A4.2: Setelah migrasi, verifikasi toolchain Xcode, deployment target macOS 13, dan build
  universal (arm64 + x86_64) tetap berjalan.
- R-A4.3: Dokumentasikan versi Xcode dan macOS SDK yang digunakan di file workflow atau
  komentar yang dapat dijadikan referensi.

---

### A5 · Perbaiki PDF→DOCX tidak muncul di roda konversi macOS

**File:** `Sources/Ceyloro/DocumentConverter.swift` baris 14–27;
`Sources/CeyloroCore/FileFormat.swift` baris 4–13, 31–48;
`Sources/CeyloroCore/DocumentConversionPolicy.swift` baris 8–24;
`Sources/Ceyloro/AppDelegate.swift` baris 300–304

**Masalah 1:** `DocumentConverter.supportedTargets()` menolak input yang bukan `kind == .document`.
PDF diklasifikasikan sebagai `kind == .pdf`, sehingga meskipun `DocumentConversionPolicy` dan
`convert()` mendukung PDF→DOCX, jalur menu menerima daftar kosong dan opsi tidak muncul.

**Masalah 2:** Pengecekan `hasExtractableText(at: files[0])` menggunakan file pertama dari batch
sebagai proxy seluruh batch — batch PDF campuran (teks + scan) dapat ditawarkan/ditolak berdasarkan
isi file pertama saja.

**Requirement:**
- R-A5.1: `DocumentConverter.supportedTargets()` harus mengizinkan `kind == .pdf` untuk pasangan
  sumber-target yang didefinisikan di policy (PDF→DOCX), tidak memblokir berdasarkan kind secara
  global.
- R-A5.2: Pengecekan teks (`hasExtractableText`) harus dilakukan per-file dalam batch, bukan hanya
  pada `files[0]`.
- R-A5.3: Target DOCX harus muncul di roda konversi macOS saat Pandoc tersedia dan file PDF
  mengandung teks yang dapat diekstrak.
- R-A5.4: Harus ada tes `wheelItems(for:mode:.convert)` untuk PDF berteks saat Pandoc tersedia.
- R-A5.5: Harus ada tes batch dengan PDF teks + PDF scan dalam dua urutan berbeda, memverifikasi
  keputusan per-file.

---

## Gelombang B — Hardening input dan proses

### B1 · Tutup bypass dotfiles pada limit ukuran ekstraksi arsip macOS

**File:** `Sources/Ceyloro/ArchiveConverter.swift` baris 95–149

**Masalah:** `expandedSize(of:)` menggunakan enumerator dengan `.skipsHiddenFiles`, sehingga file
berawalan titik tidak dihitung dalam batas 2 GB. Selain itu belum ada batas jumlah entri.

**Requirement:**
- R-B1.1: Enumerasi ukuran harus menghitung semua file termasuk dotfiles (hapus `.skipsHiddenFiles`).
- R-B1.2: Harus ada batas jumlah entri sebelum ekstraksi dimulai (setara dengan Windows: 100.000
  entri atau nilai yang sesuai dan terdokumentasi).
- R-B1.3: Validasi pra-ekstraksi harus mencakup: jumlah entri, total ukuran, path containment,
  kebijakan symbolic link, dan absolute path.
- R-B1.4: Harus ada fixture tes: arsip ZIP/TAR dengan dotfiles besar, banyak entri, path `../`,
  path absolut, dan symlink — semua harus ditolak atau dibatasi sesuai kontrak.

---

### B2 · Betulkan penamaan root arsip Windows (GUID bukan nama sumber)

**File:** `Windows/Ceyloro.Windows/ArchiveConverter.cs` baris 54–65, 147–205

**Masalah:** `SelectContentRoot()` mengembalikan direktori staging berformat GUID jika arsip
memiliki lebih dari satu root entry. `Create()` kemudian memakai nama direktori staging tersebut
sebagai `baseName`, sehingga arsip hasil memiliki prefix GUID, bukan nama arsip input.

**Requirement:**
- R-B2.1: `logicalBaseName` dari arsip input harus dibawa ke `Create()` secara terpisah dari path
  direktori staging.
- R-B2.2: Nama root arsip output harus deterministik dan berdasarkan nama arsip sumber, bukan GUID.
- R-B2.3: Harus ada tes round-trip untuk arsip dengan satu direktori root, multi-root, dan file
  langsung di root.

---

### B3 · Betulkan capability filtering GIF animasi Windows dan FFmpeg macOS

**File (Windows):** `Windows/Ceyloro.Windows/ConversionEngine.cs` baris 41–61

**File (macOS):** `Sources/CeyloroCore/FFmpegConversion.swift` baris 20–21;
`Sources/Ceyloro/EngineProbe.swift` baris 39–65

**Masalah Windows:** Target video/audio untuk GIF animasi tidak selalu mensyaratkan capability
FFmpeg yang valid; target tidak difilter berdasarkan encoder/muxer yang tersedia, sehingga wheel
bisa menampilkan opsi yang akan selalu gagal.

**Masalah macOS:** `FFmpegConversionPolicy.supports()` mengembalikan `true` saat `encoders` kosong.
`EngineProbe.probeEncoders()` juga mengembalikan set kosong saat probe gagal — kondisi "tidak
diketahui" disamakan dengan "semua didukung".

**Requirement:**
- R-B3.1: Target GIF→video/audio di Windows harus mensyaratkan FFmpeg yang valid dan encoder/muxer
  yang spesifik tersedia.
- R-B3.2: `FFmpegConversionPolicy.supports()` di macOS tidak boleh mengembalikan `true` saat daftar
  encoder kosong akibat kegagalan probe.
- R-B3.3: Status hasil probe harus dimodelkan secara eksplisit: `success(encoders)`,
  `failed`, atau `unknown` — bukan diserahkan ke nilai default.
- R-B3.4: Saat status `unknown` atau `failed`, UI tidak menampilkan target yang memerlukan encoder
  tersebut (atau melakukan reprobe terlebih dahulu).
- R-B3.5: Tes matriks untuk Windows: FFmpeg tidak ditemukan, probe gagal, encoder target tidak ada,
  semua tersedia.

---

### B4 · Drain stdout/stderr proses secara konkuren (macOS)

**File:** `Sources/Ceyloro/DocumentConverter.swift` baris 315–341;
`Sources/Ceyloro/EngineProbe.swift` baris 39–50

**Masalah:** Pola saat ini menunggu proses selesai sambil poll `isRunning`, lalu membaca pipe
setelah proses keluar. Jika pipe penuh, child process tertahan saat menulis stderr dan terjadi
deadlock.

**Requirement:**
- R-B4.1: Stdout dan stderr harus di-drain secara konkuren selama proses berjalan (menggunakan
  `readabilityHandler` atau Task/DispatchQueue terpisah).
- R-B4.2: Pembatalan dan timeout harus tetap menghentikan seluruh process tree dan membersihkan
  staging, terlepas dari kondisi pipe.
- R-B4.3: Harus ada tes dengan fake executable yang menulis stderr berukuran besar — proses harus
  selesai atau timeout dengan bersih tanpa hang.

---

### B5 · Perkuat updater macOS (validasi bundle dan rollback aman)

**File:** `Sources/Ceyloro/UpdateService.swift` baris 129–160, 164–210, 213–235

**Masalah:** `isValidAppBundle()` hanya memeriksa executable dan plist readable. Checksum diunduh
dari release yang sama (bukan trust anchor independen). `restore()` hanya mengembalikan backup jika
path aplikasi tidak ada — gagal setelah direktori parsial terbentuk tidak memicu restore. URL
`browser_download_url` tidak dibatasi allowlist host.

**Requirement:**
- R-B5.1: Staging harus dilakukan di direktori saudara yang terpisah dari instalasi aktif; app lama
  tidak boleh disentuh sebelum seluruh validasi selesai.
- R-B5.2: Validasi harus mencakup: bundle ID, versi, executable, dan code signature — tidak hanya
  keberadaan file.
- R-B5.3: Jika instalasi gagal setelah direktori parsial terbentuk, hapus instalasi parsial terlebih
  dahulu, lalu restore backup.
- R-B5.4: URL download harus dibatasi ke HTTPS dan host/domain release yang diharapkan sebelum
  request dilakukan.
- R-B5.5: Harus ada tes fault-injection: download putus, checksum salah, archive invalid, gagal
  copy, gagal relaunch.

---

### B6 · Tambahkan regression test untuk output naming/race macOS ZIP

**File:** `Sources/CeyloroCore/JobRunner.swift` baris 329–345;
`Sources/CeyloroCore/OutputNaming.swift` baris 66–95

**Masalah:** Pada jalur multi-page ZIP, `JobRunner` menghapus placeholder sebelum memulai `ditto`,
membuka jeda di mana job lain bisa memilih path yang sama.

**Requirement:**
- R-B6.1: `ditto` harus membuat ZIP ke staging path unik terlebih dahulu, bukan langsung ke path
  yang reservasinya sudah dilepas.
- R-B6.2: Setelah `ditto` sukses, lakukan move/commit ke output final dengan mekanisme
  collision-safe (tanpa melepas reservasi lebih dulu).
- R-B6.3: Harus ada tes concurrency: dua job ZIP dengan nama koleksi sama tidak pernah bertabrakan
  atau saling mengganggu.

---

## Gelombang C — Pra-production-ready

### C1 · Migrasi Windows dari .NET 8 ke .NET 10

**File:** `Windows/Ceyloro.Windows/Ceyloro.Windows.csproj`

**Masalah:** Target `net8.0-windows10.0.19041.0` mencapai end-of-support 10 November 2026. .NET 10
adalah LTS aktif (dukungan hingga November 2028).

**Requirement:**
- R-C1.1: Migrasi ke `net10.0-windows...` (TFM yang setara).
- R-C1.2: Semua tes harness Windows harus lulus setelah migrasi.
- R-C1.3: Workflow CI harus menggunakan dotnet SDK 10 yang eksplisit (pin versi di workflow).

---

### C2 · Kunci dependency dan build environment

**File:** `Windows/Ceyloro.Windows/Ceyloro.Windows.csproj`; semua workflow CI

**Masalah:** Tidak ada `packages.lock.json`, `global.json`, atau `Package.resolved`. Versi
transitive package, SDK, dan build environment tidak dikunci.

**Requirement:**
- R-C2.1: Aktifkan NuGet lock file dan `RestoreLockedMode=true` di CI.
- R-C2.2: Tambahkan `global.json` dengan versi SDK .NET eksplisit.
- R-C2.3: Dokumentasikan versi Xcode/Swift, FFmpeg, LibreOffice, dan Pandoc yang digunakan
  per release dalam artifact atau file manifest.

---

### C3 · Verifikasi checksum source FFmpeg macOS sebelum build

**File:** `scripts/build-ffmpeg-universal.sh` baris 9–16, 42–60, 157–162

**Masalah:** Script macOS tidak memverifikasi checksum/signature arsip FFmpeg sebelum ekstraksi dan
kompilasi, berbeda dengan script Windows yang mempunyai hash SHA-256 eksplisit.

**Requirement:**
- R-C3.1: Pin checksum yang diverifikasi untuk setiap versi dan arsitektur arsip FFmpeg macOS.
- R-C3.2: Script harus memverifikasi checksum segera setelah unduhan, sebelum ekstraksi.
- R-C3.3: Simpan manifest versi/hash/configure-flags/source-URL sebagai artifact release.

---

### C4 · Tambahkan smoke test ARM64 Windows dan paket release

**File:** `.github/workflows/windows-shell.yml`; `.github/workflows/release-desktop.yml`

**Masalah:** Test harness Windows hanya dijalankan untuk arsitektur x64. Paket release tidak
dijalankan sama sekali untuk memverifikasi runtime.

**Requirement:**
- R-C4.1: Jalankan test harness juga untuk arsitektur ARM64, atau dokumentasikan eksplisit bahwa
  ARM64 hanya diverifikasi build/cross-compile.
- R-C4.2: Tambahkan smoke test yang menjalankan executable hasil publish: verifikasi versi FFmpeg,
  konversi fixture gambar/PDF/arsip dasar, dan pembatalan.
- R-C4.3: Smoke test harus berjalan sebagai langkah terpisah di workflow release.

---

### C5 · Signing, notarization, dan manifest distribusi

**File:** `scripts/build-app.sh`; workflow release; README

**Masalah:** Paket macOS memakai ad-hoc signature; notarization tidak dijalankan. Windows belum
Authenticode-signed. README menyebut ukuran paket ~364 MB tanpa verifikasi artifact aktual.

**Requirement:**
- R-C5.1: Tambahkan langkah Developer ID signing + notarization + stapling ke workflow release
  macOS (kondisional pada ketersediaan secrets).
- R-C5.2: Tambahkan langkah Authenticode signing ke workflow release Windows.
- R-C5.3: Setiap artifact release harus disertai manifest: versi, OS, arsitektur, dependency,
  capability tersedia, status signature/notarization.
- R-C5.4: README tidak boleh mencantumkan ukuran paket statis; ganti dengan link ke halaman release
  atau generate dari artifact aktual.

---

## Temuan P2 dokumentasi / UX (tidak ada perubahan kode fungsional)

### D1 · Perjelas perilaku kompresi di UI

**Requirement:**
- R-D1.1: Jalur kompresi yang menghasilkan ZIP dari file dokumen (bukan optimasi internal) harus
  menampilkan label yang jelas, misalnya "Kemas ke ZIP" bukan sekadar "Kompres".
- R-D1.2: Kompresi PDF yang merasterisasi halaman harus menampilkan peringatan yang jelas bahwa
  teks, hyperlink, form, dan struktur tidak dipertahankan.
- R-D1.3: Semua jalur kompresi harus menampilkan ukuran sebelum dan sesudah; jika output lebih besar
  atau sama, informasikan pengguna.

---

### D2 · Rekonsiliasi dokumentasi dengan capability nyata

**Requirement:**
- R-D2.1: Buat atau perbarui tabel fitur per platform di README dengan kolom "tersedia pada rilis"
  vs "direncanakan".
- R-D2.2: PDF→DOCX macOS harus dicantumkan sebagai "tersedia saat Pandoc tersedia" setelah A5
  diperbaiki.
- R-D2.3: PDF→DOCX Windows harus dicantumkan sebagai "belum tersedia" hingga implementasi selesai.

---

## Urutan pengerjaan yang disepakati

```
Gelombang A  →  Gelombang B  →  Gelombang C  →  D (dokumentasi, bisa paralel dengan C)
```

Setiap item diselesaikan satu per satu secara berurutan dalam gelombangnya, dengan verifikasi
dan regression test sebelum melanjutkan ke item berikutnya.
