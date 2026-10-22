# Ceyloro Platform Linux Product Scope

**Status:** Planning Only  
**Versi:** Draft 0.1  
**Sumber:** Master Product Scope Ceyloro, PRD migrasi Linux, dan referensi visual radial wheel  
**Platform awal:** Ubuntu 22.04+ dan Fedora yang didukung toolchain  
**Arsitektur awal:** Linux `x86_64`  
**Arsitektur lanjutan:** Linux `arm64`  
**Hubungan:** Dokumen scope Linux; bukan pengganti PRD migrasi Linux yang sudah ada.

## 1. Tujuan

Menentukan bentuk produk Ceyloro di Linux dengan memakai kembali CeyloroCore dan
CeyloroEngine, tetapi membuat shell desktop baru yang menghormati perbedaan
antara GNOME, KDE, X11, Wayland, dan file manager Linux.

Linux bukan port langsung AppKit atau WinForms. Scope ini menetapkan produk yang
setara secara konsep, bukan salinan literal menu bar macOS.

## 2. Prinsip platform Linux

- Core tidak mengimpor GTK, Qt, AppKit, WinForms, X11, atau Wayland.
- Pemrosesan tetap lokal dan offline.
- File sumber tidak pernah diubah, dihapus, atau ditimpa diam-diam.
- Hotkey dan drag-and-drop menjadi jalur interaksi utama.
- Shift-drag global hanya menjadi enhancement bila desktop mengizinkan.
- Tray icon bukan satu-satunya cara menjalankan aplikasi.
- Fitur desktop-specific memiliki fallback.
- Target format mengikuti capability backend nyata.
- Root privilege tidak diperlukan untuk operasi file biasa.

## 3. Baseline arsitektur yang direncanakan

### CeyloroCore

Berisi format, naming, hit-testing, job state, output policy, cancellation,
dan aturan yang dapat diuji tanpa UI desktop.

### CeyloroEngine

Berisi capability, request, backend contract, result, progress, dan error
contract lintas-platform.

### Linux CLI

Executable headless menjadi baseline diagnosis dan automation. CLI direncanakan
memiliki input, target, output folder, compression request, JSON progress,
exit code, signal cancellation, dan engine diagnostics.

### Linux desktop shell

Shell tipis menyediakan launcher, overlay/action palette, file drop, Settings,
progress, cancellation, notification, dan diagnostics. Pilihan GTK4/libadwaita
menjadi default spike; boundary CLI/IPC menjadi fallback bila binding Swift
tidak stabil.

## 4. Model interaksi Linux

### Convert formats

Menampilkan target format yang kompatibel dengan file yang di-drop atau dipilih.

### File tools

Menampilkan Compress, Extract, Crop, Split, Metadata, dan tools lain yang
tersedia.

### File actions

Menampilkan Copy, Copy Path, Move, Open Folder, atau tindakan native yang
memang masuk akal di desktop environment yang digunakan.

### Input dan desktop environment

- Hotkey/action palette menjadi alur universal.
- Drag-and-drop ke overlay menjadi alur visual utama.
- Global Shift-drag tidak boleh menjadi satu-satunya cara membuka wheel.
- Tray indicator digunakan bila tersedia, tetapi launcher dan desktop entry
  selalu disediakan.
- XDG Desktop Portal dipakai untuk akses file, notification, URI, dan operasi
  yang memerlukan mediasi sandbox.

## 5. Radial wheel dan visual direction

Mengikuti arah referensi:

- petal aktif oranye;
- petal lain netral;
- border tipis;
- pusat wheel menunjukkan target aktif;
- ikon garis untuk tools dan actions;
- jumlah petal menyesuaikan konteks;
- keyboard navigation dan angka `1–9`;
- state probing, disabled, configuration, processing, success, error, dan
  cancelled.

Shell harus menyediakan fallback action palette bila radial overlay tidak dapat
menjadi always-on-top pada compositor tertentu.

## 6. Conversion scope Linux

### Images

JPG, PNG, WebP, HEIC, TIFF, AVIF, BMP, GIF, dan PDF bila decoder/encoder
tersedia.

### Audio

MP3, M4A, WAV, FLAC, OGG, OPUS, AIFF, dan format lain yang capability FFmpeg
mendukung.

### Video

MP4, MOV, MKV, WebM, AVI, WMV, GIF, serta video-to-audio bila encoder tersedia.

### PDF dan dokumen

PDF ke JPG/PNG/TXT/DOCX best-effort, image-to-PDF, PDF merge, serta dokumen,
slides, dan spreadsheet melalui engine yang dapat dibundel atau tersedia secara
resmi untuk target distro.

### Subtitle dan archives

SRT, VTT, TXT, ZIP, TAR, GZIP, TAR.GZ, serta Extract sebagai tool terpisah.

RAR/7Z berstatus Deferred sampai backend, lisensi, dan security review jelas.

Format di atas adalah target scope, bukan janji dukungan semua distro.

## 7. Tools scope Linux

### Prioritas awal

- Compress;
- Extract;
- PDF Split;
- PDF Organize;
- Image Crop;
- Audio Trim;
- Video Trim;
- Video Snapshot;
- Video Mute.

### Kandidat lanjutan

- Metadata;
- Redact;
- Annotate;
- Add Background;
- Normalize;
- Channels;
- Visualize;
- Bleep;
- Video Crop;
- Video Speed;
- Video Split;
- Float atau shelf yang cocok dengan desktop environment.

Tools hanya muncul ketika backend, permission, dan output semantics sudah jelas.

## 8. Desktop environment scope

### Target awal

- Ubuntu GNOME Wayland;
- Ubuntu GNOME X11;
- Fedora GNOME Wayland.

### Target berikutnya

- KDE Plasma;
- wlroots-based desktop;
- Cinnamon, MATE, Xfce, dan desktop lain setelah capability diuji.

Yang harus diverifikasi per desktop:

- global hotkey;
- tray/status indicator;
- file drag payload;
- overlay always-on-top;
- screen coordinates dan multi-monitor;
- scaling;
- portal response;
- lock, suspend, resume;
- dark mode dan high contrast.

## 9. Engine dan packaging scope

### Engine

- FFmpeg LGPL dengan versi, konfigurasi, checksum, dan notice yang dipin.
- Pandoc dan LibreOffice hanya dipromosikan sebagai bundled jika benar-benar
  dapat didistribusikan dan dijalankan pada target.
- Capability probe menyembunyikan target yang backend-nya tidak ada.
- Tidak ada download engine diam-diam saat runtime.

### Distribution

- AppImage sebagai paket portable utama.
- Flatpak sebagai paket sandboxed dengan XDG portals.
- `.deb` dan `.rpm` setelah AppImage/Flatpak stabil.
- Desktop entry, icon, metadata, license, checksum, dan release notes.
- Paket x86_64 terlebih dahulu; arm64 menjadi fase lanjutan.

## 10. Output, job, dan Settings

Output:

- folder default atau folder kustom;
- nama unik saat konflik;
- folder/ZIP untuk multi-page;
- cleanup temp dan output parsial;
- tidak mengubah file sumber.

Job:

`queued → probing → running → succeeded / failed / cancelled`

Settings:

- output folder;
- kualitas media;
- multi-page Folder/ZIP;
- engine diagnostics;
- hotkey;
- notification preference;
- startup behavior;
- preferensi tools.

## 11. QA scope

### Core dan CLI

- test CeyloroCore dan CeyloroEngine di Linux;
- path, Unicode, locale, timezone, permission, symlink;
- exit code dan JSON progress;
- SIGINT/SIGTERM;
- cancellation dan temp cleanup;
- output collision dan partial failure.

### Shell

- GNOME Wayland;
- GNOME X11;
- KDE;
- satu dan banyak monitor;
- scaling 100–200%;
- dark/light mode;
- high contrast;
- keyboard-only dan screen reader;
- launcher, tray fallback, hotkey, Escape, timeout, dan click outside.

### Media dan dokumen

- image/audio/video/PDF/subtitle/archive;
- video-to-audio;
- PDF scan, locked, rotation, dan multi-page;
- engine bundled, engine hilang, dan engine invalid;
- kompresi serta output safety.

## 12. Urutan pengerjaan yang direncanakan

1. LIN-0: feasibility spike untuk Core, Engine, Foundation, process, dan test.
2. LIN-1: Linux CLI dan capability diagnostics.
3. LIN-2: shell desktop dasar dan file drop.
4. LIN-3: radial wheel, hotkey, Settings, progress, dan notifications.
5. LIN-4: GNOME Wayland/X11 dan portal integration.
6. LIN-5: KDE compatibility dan packaging AppImage/Flatpak.
7. LIN-6: ARM64, engine matrix, performance, dan release gate.

## 13. Definition of done

PRD Linux ini siap menjadi acuan implementasi ketika:

- distro dan arsitektur tahap pertama disetujui;
- toolkit dan CLI/IPC boundary ditentukan;
- conversion dan tools matrix disetujui;
- fallback interaction untuk Wayland ditetapkan;
- engine dan packaging policy jelas;
- acceptance test desktop, file safety, dan package tersedia;
- Linux tidak dipasarkan sebagai parity penuh sebelum target desktop yang
  disepakati lulus.

## 14. Status dokumen

Dokumen ini hanya mendefinisikan scope produk Linux. Ia tidak membuat shell,
tidak menambahkan dependency, tidak mengubah CeyloroCore, dan tidak menggantikan
PRD migrasi Linux.

