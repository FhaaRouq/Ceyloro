# PRD: Migrasi Ceyloro ke Linux

**Status:** Belum dimulai / proposal implementasi  
**Platform awal:** Ubuntu 22.04+ dan Fedora yang didukung toolchain Swift  
**Arsitektur awal:** Linux `x86_64`  
**Arsitektur lanjutan:** Linux `arm64`  
**Pemilik:** Ceyloro  
**Tujuan:** membawa mesin konversi Ceyloro ke Linux tanpa menulis ulang Core dan tanpa menjanjikan parity desktop yang tidak realistis.

## 1. Ringkasan

Linux bukan target mustahil, tetapi bukan sekadar menambahkan satu build flag.
`CeyloroCore` dan `CeyloroEngine` dapat menjadi fondasi portable, sedangkan
AppKit macOS dan WinForms Windows harus diganti dengan shell Linux baru.

PRD ini mendefinisikan migrasi bertahap: headless engine terlebih dahulu,
kemudian desktop shell, integrasi file, bundling dependency, packaging, dan
validasi pada beberapa desktop environment.

Swift mendukung development dan deployment Linux pada Ubuntu, Debian, Fedora,
Amazon Linux, dan Red Hat Universal Base Image. Swift Foundation juga memiliki
implementasi portable di luar Objective-C runtime Apple. Detail versi minimum
dan distribusi harus dipin pada CI setiap release, bukan diasumsikan dari
mesin developer. ([Swift Platform Support](https://www.swift.org/platform-support/),
[Swift About](https://www.swift.org/about/))

## 2. Kondisi awal

### Yang dapat dipakai ulang

- `CeyloroCore` sebagai aturan format, naming, hit-testing, job, dan policy.
- `CeyloroEngine` sebagai kontrak request, capability, backend, dan hasil.
- Test pure Swift yang tidak memerlukan AppKit.
- Matriks format dan aturan output yang sudah dipakai macOS/Windows.
- Kontrak FFmpeg, Pandoc, LibreOffice, progress, cancellation, dan temp.

### Yang belum tersedia

- Linux executable atau Linux target di package/workflow.
- Tray icon dan radial overlay Linux.
- Integrasi Nautilus, Dolphin, Nemo, Thunar, dan file manager lainnya.
- Global hotkey dan drag monitoring yang konsisten di X11 dan Wayland.
- Permission/file portal strategy.
- Paket AppImage, Flatpak, `.deb`, atau `.rpm`.
- Bundling dependency Linux per distro dan arsitektur.
- Test matrix desktop environment dan hardware.

## 3. Prinsip produk Linux

1. Converter tetap offline dan tidak mengubah file sumber.
2. Core tidak mengimpor GTK, Qt, AppKit, WinForms, X11, atau Wayland.
3. Linux tidak dipasarkan sebagai salinan persis Finder/menu bar macOS.
4. Hotkey dan drag-and-drop menjadi dua jalur yang sama-sama didukung.
5. Fitur yang bergantung desktop environment harus memiliki fallback.
6. Target format selalu berdasarkan capability nyata dari backend lokal.
7. Paket final harus dapat dipakai tanpa pengguna memasang FFmpeg, Pandoc, atau
   LibreOffice manual untuk fitur yang dipromosikan bundled.

## 4. Tujuan dan non-tujuan

### Tujuan

- Menjalankan `CeyloroCore` dan `CeyloroEngine` di Linux.
- Menyediakan CLI/headless converter sebagai fondasi dan alat diagnosis.
- Menyediakan shell desktop radial dengan tray atau launcher yang sesuai.
- Mendukung Ubuntu dan Fedora terlebih dahulu.
- Mendukung Linux x86_64 terlebih dahulu, lalu arm64.
- Menyediakan AppImage dan Flatpak sebagai kanal distribusi utama.
- Menyediakan capability probe, progress, cancellation, compression, output
  folder, dan cleanup yang konsisten dengan platform lain.

### Bukan tujuan tahap pertama

- Menjamin menu bar universal di semua desktop environment.
- Menjamin Shift-drag global identik dengan Finder pada Wayland.
- Mendukung semua distribusi Linux dan semua compositor sejak release pertama.
- Mengubah CeyloroCore menjadi library C/C++ tanpa kebutuhan nyata.
- Menambahkan cloud sync atau telemetri.
- Menggunakan root privilege untuk operasi file biasa.

## 5. Keputusan arsitektur

### L1 — Lapisan portable

Pastikan target Linux untuk `CeyloroCore` dan `CeyloroEngine` hanya memakai API
Foundation/Swift yang tersedia lintas-platform. Pisahkan:

- format dan conversion planning;
- job state, progress, cancellation, dan result;
- naming, output policy, dan temp cleanup;
- backend protocol;
- platform process/file adapter.

Tidak boleh ada conditional import desktop UI di Core.

### L2 — Headless Linux executable

Buat executable `ceyloro-cli` untuk Linux dengan interface yang dapat diuji,
misalnya:

- input file dan target format;
- output directory;
- compression request;
- JSON progress ke stdout atau IPC;
- exit code terdefinisi;
- cancellation melalui signal;
- diagnostic command untuk capability dan engine version.

CLI bukan pengganti UI; ia menjadi baseline untuk automation, smoke test,
support, dan fallback ketika shell desktop bermasalah.

### L3 — Desktop shell

Default recommendation: buat shell GTK4/libadwaita yang tipis dan memanggil
Core/Engine atau executable headless melalui kontrak lokal yang stabil. Jika
spike binding Swift–GTK tidak cukup stabil, gunakan shell bahasa lain dengan
CLI/IPC sebagai boundary, tanpa memindahkan aturan bisnis ke shell.

Shell minimal harus memiliki:

- radial overlay atau action palette;
- file drop target;
- daftar target berdasarkan capability;
- progress per job;
- cancellation;
- output folder dan Settings;
- notifikasi sukses/gagal;
- diagnostics engine;
- launcher/desktop entry;
- tray indicator bila desktop environment mendukungnya.

### L4 — Model interaksi Linux

Linux memiliki X11, Wayland, banyak compositor, dan beberapa file manager.
Karena itu kontrak Linux adalah:

- hotkey/palette sebagai alur universal;
- drag-and-drop ke overlay sebagai alur utama UI;
- Shift-drag global sebagai enhancement yang hanya diaktifkan bila backend
  desktop mengizinkannya;
- tidak membaca pointer atau clipboard global secara agresif;
- tidak meminta root privilege;
- memakai XDG Desktop Portal untuk akses yang memerlukan mediasi sandbox.

XDG Desktop Portal menyediakan interface D-Bus untuk akses file dan integrasi
desktop yang aman, dengan backend berbeda untuk GNOME, KDE, wlroots, Xapp, dan
desktop environment lain. ([XDG Desktop Portal](https://flatpak.github.io/xdg-desktop-portal/docs/))

## 6. Dukungan desktop environment

### Release awal

- Ubuntu GNOME pada Wayland.
- Ubuntu GNOME pada X11.
- Fedora GNOME pada Wayland.
- KDE Plasma sebagai compatibility target berikutnya.

### Yang harus diukur, bukan diasumsikan

- global hotkey;
- tray/status indicator;
- file drag payload;
- overlay always-on-top;
- screen coordinates dan multi-monitor;
- screen scaling;
- portal response;
- lock/suspend/resume;
- dark mode dan high contrast.

Jika tray tidak tersedia, Ceyloro harus tetap dapat dijalankan dari launcher
dan hotkey daemon/shell yang disediakan oleh desktop environment.

## 7. Backend dan dependency

### FFmpeg

- Sediakan binary atau package FFmpeg LGPL yang kompatibel dengan target distro.
- Pin versi, konfigurasi, checksum, dan license notice.
- Jangan mengaktifkan GPL/nonfree encoder tanpa keputusan lisensi eksplisit.
- Capability probe harus menyembunyikan target yang tidak tersedia.

### Pandoc dan LibreOffice

- Tentukan apakah bundled melalui AppImage, extension, atau package runtime.
- Dokumentasikan ukuran dan license notice.
- Uji binary pada Ubuntu dan Fedora yang didukung.
- Bila engine tidak dapat dibundel untuk suatu arsitektur, sembunyikan target
  dokumen dan tampilkan alasan yang dapat ditindaklanjuti.

### GTK dan platform libraries

- Pin versi minimum GTK4/libadwaita atau toolkit yang dipilih.
- Hindari ketergantungan desktop-specific di Core.
- Catat library runtime pada manifest paket.
- Pastikan theme dan accessibility API tidak menjadi hard dependency yang
  hanya tersedia pada satu desktop environment.

## 8. Packaging dan distribusi

### AppImage

- Sediakan satu paket x86_64 yang self-contained.
- Sertakan desktop entry, icon, metadata, license, dan update information.
- Verifikasi pada Ubuntu dan Fedora tanpa instalasi dependency manual.
- Pastikan AppImage tidak menjalankan file dari lokasi yang belum diverifikasi.

### Flatpak

- Buat manifest resmi dengan runtime yang dipin.
- Gunakan portal untuk file access, notifications, opening folders, dan
  integration yang diperlukan.
- Minimalkan permission filesystem.
- Uji update melalui remote repository.
- Sediakan release notes dan checksum.

### Paket distro

`.deb` dan `.rpm` dapat ditambahkan setelah AppImage/Flatpak stabil. Paket distro
harus mendokumentasikan dependency sistem dan tidak boleh diam-diam mengunduh
binary saat runtime.

## 9. Test strategy

### Core

- Jalankan seluruh test CeyloroCore di Linux.
- Tambahkan test path, Unicode, locale, timezone, file permission, symlink,
  cancellation, dan process exit.
- Pastikan hasil dan naming konsisten dengan macOS/Windows.

### CLI

- Test exit code untuk sukses, input invalid, backend hilang, cancellation,
  partial failure, dan output collision.
- Test JSON progress tidak rusak oleh log biasa.
- Test SIGINT/SIGTERM tidak meninggalkan temp atau output parsial.

### Shell

- Test overlay dan drop di GNOME Wayland, GNOME X11, dan KDE.
- Test satu dan banyak monitor.
- Test scaling 100%, 125%, 150%, dan 200%.
- Test dark/light mode, high contrast, keyboard-only, dan screen reader.
- Test launcher, tray fallback, hotkey, timeout, Escape, dan click outside.

### Media dan dokumen

- Uji representative image/audio/video/PDF/subtitle/archive.
- Uji PDF multi-page, TIFF multi-page, PDF scan, PDF locked, dan PDF rotation.
- Uji video ke audio untuk seluruh target yang capability-nya tersedia.
- Uji dokumen dengan engine bundled dan engine tidak tersedia.
- Uji kompresi tidak merusak file sumber.

## 10. CI/CD Linux

Matrix minimum:

- Ubuntu 22.04 x86_64;
- Ubuntu latest supported x86_64;
- Fedora supported x86_64;
- Ubuntu arm64 setelah x86_64 stabil.

Pipeline harus:

1. build Core dan Engine;
2. run test suite;
3. build CLI;
4. build shell;
5. stage dan verify FFmpeg/document engines;
6. build AppImage dan Flatpak;
7. inspect permissions dan package contents;
8. create checksums and release manifest;
9. publish preview channel sebelum stable.

Build Linux sebaiknya dilakukan di runner/container Linux yang sesuai. Swift
menyediakan toolchain dan SDK Linux, tetapi target Linux tidak boleh dianggap
teruji hanya karena build macOS berhasil. Dokumentasi Swift juga membedakan
lingkungan build Linux dan cross-compilation, sehingga CI Linux native tetap
menjadi gate wajib. ([Swift Linux installation](https://www.swift.org/install/linux/ubuntu/),
[Swift packaging](https://www.swift.org/documentation/server/guides/packaging.html))

## 11. Urutan fase migrasi

### L0 — Feasibility spike

- Build `CeyloroCore` dan `CeyloroEngine` di Ubuntu.
- Verifikasi Foundation, process execution, file coordination, dan tests.
- Ukur Swift–GTK binding atau CLI/IPC fallback.
- Putuskan toolkit dan boundary shell.

### L1 — Linux CLI

- Implementasikan conversion, compression, capability, progress, cancellation,
  output naming, dan diagnostics.
- Jalankan sampel format dan regression suite.

### L2 — Linux shell dasar

- Launcher, settings, file drop, action palette/radial overlay, progress,
  cancellation, notifications, dan output folder.

### L3 — Desktop integration

- XDG portals, GNOME Wayland, GNOME X11, KDE, tray fallback, multi-monitor,
  hotkey, and file manager behavior.

### L4 — Packaging

- AppImage, Flatpak, license/notice, checksum, release notes, dan update path.

### L5 — ARM64 dan release hardening

- Native ARM64 build, engine availability, device tests, performance, memory,
  and stable-channel release.

## 12. Risiko dan mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Global input dibatasi Wayland | Shift-drag tidak universal | Hotkey dan drop-to-overlay menjadi fallback resmi |
| Tray tidak tersedia | Ikon tidak muncul di sebagian desktop | Launcher, notification, dan action palette tetap tersedia |
| Library GTK berbeda antar distro | UI atau runtime gagal | AppImage/Flatpak dengan runtime terkontrol |
| LibreOffice besar atau tidak tersedia ARM64 | Paket sangat besar/fitur dokumen hilang | Pisahkan engine, capability probe, dan kebijakan target per arsitektur |
| Swift binding GTK tidak stabil | Jadwal shell tertunda | CLI/IPC boundary dan spike L0 |
| FFmpeg codec berbeda | Target tidak konsisten | Capability probe dan manifest build |
| Permission portal berbeda | File tidak dapat diakses | Gunakan portal, pesan error jelas, dan fallback file picker |

## 13. Definition of done

- `CeyloroCore` dan `CeyloroEngine` lulus test di Linux.
- CLI Linux dapat mengonversi dan mengompres sampel utama tanpa dependency
  manual yang tidak didokumentasikan.
- Shell berjalan pada Ubuntu GNOME Wayland dan X11.
- File drop, hotkey, overlay, progress, cancellation, notification, dan output
  folder bekerja.
- AppImage dan Flatpak dapat dipasang pada mesin bersih.
- Tidak ada target yang tampil jika backend atau engine tidak tersedia.
- File sumber tidak pernah diubah, dihapus, atau ditimpa.
- AppImage/Flatpak memiliki license notice, checksum, dan release notes.
- README menyebut Linux sebagai **Preview** sampai minimal Ubuntu GNOME Wayland,
  GNOME X11, dan satu jalur KDE lulus.

