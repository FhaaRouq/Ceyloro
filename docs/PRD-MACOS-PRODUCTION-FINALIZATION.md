# PRD: Finalisasi Ceyloro untuk macOS

**Status:** Draft untuk pekerjaan lanjutan  
**Platform:** macOS 13 atau lebih baru  
**Arsitektur:** Intel `x86_64` dan Apple Silicon `arm64`  
**Pemilik:** Ceyloro  
**Tujuan:** mengubah build macOS dari preview yang sudah usable menjadi distribusi publik yang aman, dapat diperbarui, dan tervalidasi.

## 1. Ringkasan

Ceyloro untuk macOS sudah memiliki MVP yang luas: menu bar, radial wheel,
Shift-drag dari Finder, konversi batch, media melalui FFmpeg, dokumen,
kompresi, PDF gabungan, progress, pembatalan, Settings, dan updater GitHub.

Pekerjaan yang tersisa bukan lagi membangun converter utama dari nol. Fokus PRD
ini adalah release hardening: signing dan notarization, packaging, updater yang
aman, bundling engine dokumen, pengujian perangkat nyata, serta penyelesaian
edge case desktop macOS.

## 2. Kondisi awal

### Sudah tersedia

- App universal untuk Intel dan Apple Silicon.
- Target minimum macOS 13+.
- FFmpeg LGPL universal dapat dibundel.
- Pandoc dan LibreOffice dapat distage ke dalam app.
- Konversi gambar, PDF, audio, video, subtitle, arsip, dokumen,
  spreadsheet, dan presentasi.
- Kompresi gambar, audio, video, PDF, dan dokumen umum.
- Batch tetap lanjut ketika satu file gagal.
- Progress per job, pembatalan, output unik, cleanup temp, dan laporan error.
- Multi-page output sebagai folder atau ZIP.
- Penggabungan beberapa gambar menjadi PDF.
- Menu bar, radial wheel, keyboard navigation, angka `1–9`, dan fallback
  `Shift + Spasi`.
- Updater macOS yang mengambil release resmi, memeriksa checksum, mengganti
  app di lokasi yang sama, lalu relaunch.
- Release ZIP dan checksum SHA-256.

### Belum selesai

- Developer ID signing dan Apple notarization.
- Installer/distribution image yang lebih profesional daripada ZIP saja.
- Pipeline release yang menyimpan bukti build dan metadata dependency secara
  lengkap.
- Pengujian langsung pada kombinasi macOS, Intel, Apple Silicon, monitor,
  Finder, izin sistem, dan lokasi instalasi.
- Hardening updater untuk rollback, kegagalan jaringan, dan aplikasi yang
  berada di folder berbeda.
- Audit akhir terhadap engine dokumen, FFmpeg, lisensi, dan ukuran paket.
- Penyelesaian edge case UI dan desktop integration sebelum status production.

## 3. Tujuan

1. Pengguna dapat mengunduh satu paket macOS resmi, membukanya tanpa pesan
   “damaged” palsu, dan memperoleh instruksi Gatekeeper yang jelas bila build
   belum ditandatangani.
2. Build production ditandatangani, dinotarize, dan dapat diverifikasi.
3. Updater tidak pernah meninggalkan app setengah tertimpa atau menghapus versi
   lama sebelum versi baru tervalidasi.
4. FFmpeg, Pandoc, dan LibreOffice yang dijanjikan benar-benar berada di dalam
   paket release atau target terkait disembunyikan dengan jelas.
5. Perilaku inti tervalidasi di Intel dan Apple Silicon tanpa mengubah file
   sumber pengguna.
6. Setiap release dapat dibangun ulang dari tag dengan hasil dan checksum yang
   dapat diaudit.

## 4. Bukan tujuan PRD ini

- Menambah format konversi baru yang tidak ada di matriks saat ini.
- Menulis ulang CeyloroCore atau CeyloroEngine.
- Membuat versi Windows atau Linux.
- Menambahkan cloud upload, telemetry, atau akun pengguna.
- Mengubah lisensi open-core yang sudah diputuskan.

## 5. Workstream implementasi

### M1 — Signing, entitlements, dan notarization

#### Kebutuhan

- Gunakan Apple Developer ID Application untuk app production.
- Aktifkan Hardened Runtime dengan entitlements seminimal mungkin.
- Pastikan penggunaan subprocess FFmpeg, updater, akses file, dan engine
  dokumen kompatibel dengan Hardened Runtime.
- Sign seluruh nested code dan helper sebelum sign app utama.
- Notarize ZIP atau DMG menggunakan `notarytool`.
- Staple ticket notarization ke app jika format distribusi mendukung.
- Verifikasi dengan `codesign --verify`, `spctl`, dan pemeriksaan ticket.
- Jangan menyimpan sertifikat, password, atau API key di repository.
- Gunakan GitHub Actions secrets dan keychain sementara di runner.

#### Acceptance criteria

- App production dapat dibuka dari Downloads pada Mac yang bersih tanpa
  peringatan “damaged”.
- `codesign --verify --deep --strict` lulus.
- `spctl --assess --type execute` lulus untuk app yang sudah notarized.
- Tidak ada private key atau credential muncul di artifact, log, atau cache.

### M2 — Packaging dan dependency manifest

- Tetap hasilkan satu binary universal `x86_64 + arm64`.
- Sediakan minimal ZIP release; pertimbangkan DMG sebagai pengalaman instalasi
  utama setelah pipeline signing stabil.
- Sertakan `LICENSE-APP.md`, lisensi FFmpeg, notice Pandoc/LibreOffice, dan
  checksum dependency yang benar-benar dipakai.
- Sertakan versi dan arsitektur setiap engine di halaman About atau log build.
- Pastikan tidak ada `._*`, file AppleDouble, file debug, atau cache build di
  dalam archive.
- Verifikasi bahwa `Info.plist`, icon, bundle identifier, dan version/build
  konsisten dengan tag release.
- Ukur ukuran paket terkompresi dan tidak terkompresi; dokumentasikan alasan
  bila ukuran berubah signifikan.

#### Acceptance criteria

- Paket bersih dapat diekstrak di Downloads tanpa merusak signature.
- `ffmpeg`, `pandoc`, dan `soffice` yang dijanjikan executable dan dapat
  dipanggil oleh app.
- Paket tidak mengharuskan pengguna memasang engine manual untuk target yang
  dipromosikan sebagai bundled.

### M3 — Updater yang aman

Updater yang sudah ada menjadi dasar, lalu diperkuat dengan:

- hanya menerima release dari repository resmi;
- hanya memilih versi yang lebih baru dari versi terpasang;
- validasi checksum sebelum app lama disentuh;
- staging download di folder temporary yang unik;
- validasi ZIP, bundle identifier, executable utama, signature, dan versi;
- backup atau rename atomik terhadap app lama;
- rollback jika pemindahan atau relaunch gagal;
- penanganan app berada di Downloads, Applications, folder cloud, atau folder
  yang tidak writable;
- pesan yang membedakan tidak ada update, jaringan gagal, checksum gagal,
  permission gagal, dan update berhasil;
- tampilan release notes dan ukuran download;
- log update lokal tanpa menyimpan credential atau path sensitif berlebihan.

#### Acceptance criteria

- Update berhasil dari Downloads tanpa instalasi ulang manual.
- Update gagal aman jika checksum salah atau ZIP rusak.
- App lama tetap tersedia jika update gagal sebelum commit penggantian.
- Pembaruan tidak menjalankan binary dari folder temporary sebelum validasi.
- Release yang sama tidak ditawarkan sebagai update.

### M4 — Runtime dan desktop integration

Verifikasi dan perbaiki bila diperlukan:

- Accessibility dan Automation permission pada first run.
- Shift-drag dari Finder pada satu dan banyak file.
- Shortcut `Shift + Spasi` dengan Finder aktif dan Finder tidak aktif.
- Drop di luar roda sebagai pembatalan, termasuk di tepi Dock dan menu bar.
- Overlay penuh pada monitor tempat pointer berada.
- Multi-monitor dengan koordinat negatif dan DPI berbeda.
- App Nap, sleep/wake, lock/unlock, dan perubahan ruang desktop.
- Quit ketika job masih berjalan.
- Relaunch setelah Settings atau progress window ditutup.
- Single-instance behavior dan icon menu bar tunggal.
- Akses folder Desktop, Documents, Downloads, removable volume, dan folder
  yang memerlukan security-scoped bookmark.
- Truncation nama file, Unicode, path panjang, dan nama dengan emoji.

### M5 — Konversi dan quality gate

- Uji orientasi EXIF untuk JPEG, HEIC, PNG, TIFF, dan PDF hasil kamera.
- Uji Display P3, alpha, transparansi PNG ke JPG, dan metadata yang memang
  dipertahankan atau sengaja dihapus.
- Uji PDF terkunci, crop box, rotation, halaman besar, halaman kosong, dan PDF
  hasil scan.
- Uji TIFF multi-page, PDF multi-page, folder output, ZIP output, dan zero
  padding nama halaman.
- Uji batch campuran dengan satu atau beberapa file gagal.
- Uji pembatalan saat antre, saat render, saat FFmpeg berjalan, dan saat
  archive sedang dibuat.
- Uji target yang disembunyikan ketika encoder atau decoder tidak tersedia.
- Uji hasil kompresi tidak menimpa sumber dan tetap dapat dibuka.

### M6 — CI, release governance, dan dukungan

- Tag release menjalankan test, build, dependency verification, packaging,
  signing, notarization, checksum, dan publish dalam urutan yang dapat diaudit.
- Pisahkan workflow preview dan production.
- Simpan SBOM atau manifest komponen pihak ketiga setiap release.
- Buat release notes yang mencantumkan perubahan, known issues, dan checksum.
- Tambahkan smoke test terhadap app hasil archive, bukan hanya source build.
- Rotasi log, sanitasi path, dan dokumentasi lokasi log untuk support.
- Tetapkan kebijakan support: macOS 13+ dan dua arsitektur saat ini.

## 6. Hal eksternal yang harus disiapkan

- Apple Developer Program dan akses Developer ID.
- Sertifikat Developer ID Application serta credential notarization.
- Secrets GitHub Actions untuk signing dan notarization.
- Minimal satu Mac Intel dan satu Mac Apple Silicon untuk verifikasi manual.
- Sampel file nyata yang legal untuk distribusi internal.
- Keputusan final ZIP versus DMG sebagai kanal utama.
- Review legal terhadap redistribusi Pandoc, LibreOffice, FFmpeg, dan
  komponen pihak ketiga lainnya.

## 7. Urutan pengerjaan

1. M1: signing lokal dan verifikasi Hardened Runtime.
2. M2: packaging bersih dan manifest dependency.
3. M3: updater rollback dan failure handling.
4. M4: verifikasi desktop integration dan multi-monitor.
5. M5: quality matrix dan regression tests.
6. M6: workflow production, release notes, dan pilot release.

## 8. Definition of done

- `swift test` dan build universal lulus.
- App signed, notarized, dan dapat dibuka pada Mac Intel serta Apple Silicon
  yang bersih.
- Paket release berisi dependency yang dijanjikan, lisensi, dan checksum.
- Updater berhasil dan aman untuk app di Downloads maupun Applications.
- Semua acceptance test M4 dan M5 memiliki hasil terdokumentasi.
- Tidak ada file sumber yang berubah, terhapus, atau tertimpa.
- Status di README dapat diubah dari **Preview** menjadi **Production** hanya
  setelah seluruh gate di atas lulus.

