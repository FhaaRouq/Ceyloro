# PRD Roadmap Implementasi Ceyloro macOS

**Status:** Planning Only  
**Versi:** Draft 0.1  
**Sumber:** PRD Platform macOS Ceyloro, Master PRD, dan referensi visual radial wheel  
**Platform:** macOS 13+  
**Arsitektur:** Intel `x86_64` dan Apple Silicon `arm64`  
**Catatan:** Dokumen ini adalah rencana implementasi. Tidak ada fitur di sini yang dianggap selesai hanya karena terdapat pada screenshot.

## 1. Ringkasan

Rencana macOS ini bertujuan menyelesaikan dan memvalidasi pengalaman Ceyloro
yang menyatu dengan Finder, menu bar, dan radial wheel. Fokusnya bukan menambah
fitur secara acak, tetapi menutup gap antara baseline codebase, Master PRD, dan
referensi visual.

Prioritasnya adalah keselamatan file, interaksi yang dapat diprediksi,
capability yang akurat, pemisahan Convert/Tools/Actions, dan QA pada Intel serta
Apple Silicon.

## 2. Kondisi awal

Baseline saat ini mencatat atau menyediakan sebagian besar hal berikut:

- menu bar/accessory app;
- Shift-drag dari Finder;
- `Shift + Space` sebagai fallback;
- radial overlay;
- conversion media dan dokumen tertentu;
- FFmpeg dan AVFoundation;
- progress, cancellation, batch, dan cleanup;
- output folder, kualitas, dan PDF merge;
- beberapa file actions;
- build universal Intel dan Apple Silicon.

Status setiap item tetap harus diverifikasi melalui source, automated tests, dan
runtime smoke test sebelum diberi label Existing.

## 3. Tujuan

- Menjadikan Finder drag workflow cepat dan aman.
- Menampilkan wheel yang lebih ringan, jelas, dan konsisten dengan referensi.
- Menyediakan target berdasarkan capability nyata.
- Memisahkan Convert, Tools, dan Actions secara tegas.
- Menjaga file sumber tetap utuh.
- Menyediakan feedback lengkap dari probing sampai hasil akhir.
- Menyiapkan dasar macOS production release setelah seluruh QA selesai.

## 4. Bukan tujuan

- Mengimplementasikan semua tools referensi dalam satu iterasi.
- Menganggap Move, Float, Pages, atau PDF advanced conversion sudah tersedia.
- Mengubah shell Windows atau Linux.
- Menjanjikan fidelity penuh pada format kompleks.
- Menjadikan screenshot sebagai spesifikasi pixel-perfect.

## 5. Fase MAC-0 — Keputusan dan baseline freeze

Sebelum pengerjaan teknis, tetapkan:

- minimum macOS resmi;
- modifier Convert, Tools, dan Actions;
- apakah modifier ditahan sejak drag atau ditekan setelah drag dimulai;
- apakah Tools memakai Command atau Option;
- cakupan Move dan Float;
- dukungan Pages dan permission Automation;
- cakupan RAR/7Z dan archive extraction;
- engine dokumen resmi;
- ZIP atau DMG sebagai kanal distribusi utama;
- status setiap requirement dari PRD terhadap codebase terbaru.

Output fase:

- decision log;
- baseline matrix;
- daftar fitur Existing, Partial, Verify, Placeholder, Proposed, dan Deferred.

## 6. Fase MAC-1 — Finder interaction dan lifecycle

### Requirement

- Shift-drag file tunggal membuka wheel.
- Shift-drag multi-file mempertahankan sesi drag.
- Drag folder memiliki perilaku yang jelas.
- `Shift + Space` mengambil selection Finder ketika permission tersedia.
- Accessibility permission dijelaskan sebelum diminta.
- Automation permission memiliki error state yang dapat ditindaklanjuti.
- Dismissal melalui Escape, drop di luar wheel, atau akhir drag aman.
- Overlay tidak meneruskan drop ke Finder atau aplikasi di bawahnya.
- Wheel tetap berada dalam visible frame dan tidak tertutup Dock/menu bar.
- Multi-monitor dan koordinat negatif bekerja.
- Single-instance, launch at login, sleep/wake, dan quit memiliki lifecycle yang
  konsisten.

### Acceptance criteria

- Tidak ada wheel yang muncul dari klik biasa atau pasteboard drag lama.
- Tidak ada file yang berpindah saat pengguna bermaksud membatalkan.
- Tidak ada overlay yang tertinggal setelah drag gagal atau timeout.
- Aplikasi tetap dapat dibuka kembali setelah Settings atau progress ditutup.

## 7. Fase MAC-2 — Radial wheel visual dan state system

### Arah visual referensi

- dasar netral putih/abu-abu terang;
- petal aktif oranye;
- petal lain netral dengan border tipis;
- sudut membulat dan ruang antarelemen yang cukup;
- label pendek dan terbaca;
- ikon garis untuk tools dan actions;
- pusat wheel menunjukkan target aktif;
- ukuran wheel menyesuaikan jumlah petal dan ruang layar.

Dark mode harus menggunakan warna sistem yang setara, bukan menggandakan layout
secara terpisah.

### State yang harus dirancang

- normal;
- hover/focus;
- probing/loading;
- disabled atau tidak kompatibel;
- konfigurasi;
- processing;
- success;
- error;
- cancelled;
- empty/no compatible operation.

### Keyboard

- arrow navigation;
- Return untuk memilih;
- Escape untuk membatalkan;
- angka `1–9` untuk petal yang terlihat;
- fokus keyboard tidak boleh tersembunyi oleh animasi.

## 8. Fase MAC-3 — Capability catalog dan conversion wheel

Conversion wheel akan menggunakan registry, bukan daftar statis.

### Kategori yang direncanakan

- Images: JPG, PNG, WebP, HEIC, TIFF, AVIF, BMP, PDF.
- Audio: MP3, M4A, WAV, FLAC, OGG, OPUS, AIFF, WMA.
- Video: MP4, MOV, MKV, WebM, AVI, WMV, GIF, serta audio extraction.
- PDF: JPG, PNG, TXT, DOCX, dan target lain hanya jika engine serta fidelity
  sudah disetujui.
- Documents: DOCX, Pages, Markdown, TXT, EPUB, HTML.
- Slides: PPT/PPTX, PDF, JPG, PNG.
- Spreadsheets: XLS/XLSX, ODS, CSV, TSV, PDF.
- Subtitles: SRT, VTT, TXT.
- Archives: ZIP, TAR, GZIP, dan extraction bila tool-nya siap.

### Persyaratan

Setiap petal harus tahu:

- apakah ia input atau output;
- engine yang diperlukan;
- apakah backend tersedia pada Mac tersebut;
- apakah batch/multi-page didukung;
- apakah progress dan cancel didukung;
- apa batasan fidelity-nya;
- pesan error jika target tidak dapat digunakan.

Format seperti Pages, PDF ke PPTX/XLSX/EPUB, RAR, dan 7Z tetap berstatus
Verify/Proposed sampai engine dan hasilnya diuji.

## 9. Fase MAC-4 — Pemisahan Tools wheel

Tools harus memiliki mode dan modifier yang jelas, serta tidak boleh jatuh ke
Actions secara diam-diam ketika belum ada tool yang tersedia.

### Prioritas tools

#### Prioritas pertama

- Compress;
- Extract;
- PDF Split;
- PDF Organize;
- Image Crop;
- Image Add Background.

#### Prioritas kedua

- Audio Trim;
- Audio Normalize;
- Video Trim;
- Video Snapshot;
- Video Mute;
- Metadata read/remove yang ruang lingkupnya jelas.

#### Prioritas lanjutan

- Redact;
- Annotate;
- Audio Bleep;
- Audio Channels;
- Audio Visualize;
- Video Crop;
- Video Speed;
- Video Split;
- Video Metadata;
- Float.

Setiap tool harus mempunyai definisi input, output, parameter, preview atau
konfirmasi bila relevan, progress, cancel, output naming, dan failure mode.

## 10. Fase MAC-5 — File actions

### Existing/Verify

- Copy;
- Copy Path;
- Open in Terminal atau iTerm2;
- AirDrop.

### Placeholder/Proposed

- Move;
- Float.

### Requirement Move

- dialog pemilihan folder;
- konflik nama;
- izin akses;
- cross-volume behavior;
- pembatalan;
- rollback atau laporan kegagalan;
- tidak menghapus sumber sebelum hasil pemindahan terkonfirmasi.

### Requirement Float

- shelf mengambang;
- pin/unpin ke tepi layar;
- drag item dari shelf ke aplikasi lain;
- lifecycle saat aplikasi ditutup;
- multi-monitor;
- batas jumlah item dan cleanup.

Move dan Float tidak boleh muncul sebagai petal aktif sebelum seluruh requirement
dan QA-nya terpenuhi.

## 11. Fase MAC-6 — Output, job, dan Settings

### Output

- default di samping file sumber atau folder kustom;
- nama konflik menghasilkan nama unik;
- multi-page dapat menjadi folder atau ZIP;
- sumber tidak pernah ditimpa;
- output parsial dibersihkan atau diberi status yang jelas.

### Job

Gunakan status:

`queued → probing → running → succeeded / failed / cancelled`

Tambahkan `cancelling` jika operasi memerlukan waktu untuk berhenti.

### Settings

- output folder;
- kualitas JPG/HEIC bila tersedia;
- multi-page Folder/ZIP;
- launch at login;
- FFmpeg path kustom;
- konfirmasi PDF merge;
- pilihan modifier jika disetujui;
- pengaturan tools bila tool terkait sudah tersedia.

## 12. Fase MAC-7 — QA dan release gate

### Hardware dan OS

- Intel Mac;
- Apple Silicon Mac;
- minimum macOS resmi;
- versi macOS terbaru yang ditargetkan.

### Interaction

- Finder file tunggal, batch, folder, dan cancellation;
- Accessibility diberikan, ditolak, dan dicabut;
- Automation diberikan dan ditolak;
- multi-monitor, scaling, Dock, menu bar, dan fullscreen.

### Engine

- AVFoundation encoder tersedia/tidak tersedia;
- FFmpeg bundled, custom, hilang, dan invalid;
- Pandoc/LibreOffice tersedia, invalid, dan tidak tersedia;
- target disembunyikan saat backend tidak mampu memprosesnya.

### File safety

- konflik nama;
- folder read-only;
- disk penuh;
- file terkunci;
- path Unicode dan panjang;
- cancel saat antre, render, FFmpeg, document engine, dan archive.

### Release

- universal build;
- app bundle smoke test;
- dependency manifest;
- checksum;
- signing/notarization ketika sudah masuk scope release;
- updater dari Downloads dan Applications;
- release notes dan known issues.

## 13. Urutan implementasi

1. MAC-0: keputusan dan baseline freeze.
2. MAC-1: Finder interaction dan lifecycle.
3. MAC-2: visual wheel dan state system.
4. MAC-3: capability registry dan conversion catalog.
5. MAC-4: Tools wheel prioritas pertama.
6. MAC-5: file actions, hanya yang sudah disetujui.
7. MAC-6: job, output, dan Settings.
8. MAC-7: QA, packaging, signing, dan release gate.

## 14. Definition of done

PRD macOS ini dianggap selesai ketika:

- setiap requirement memiliki status dan acceptance criteria;
- wheel Convert, Tools, dan Actions tidak tercampur;
- petal hanya muncul berdasarkan capability nyata;
- fitur placeholder tidak tampil sebagai fitur aktif;
- Finder interaction aman pada Intel dan Apple Silicon;
- conversion, tools, actions, progress, cancellation, dan output memiliki test;
- visual direction referensi diterapkan secara konsisten tanpa mengorbankan
  dark mode dan accessibility;
- release gate macOS lulus.

## 15. Status dokumen

Dokumen ini hanya merupakan PRD perencanaan. Pembuatan fitur, perubahan source,
perubahan UI, penggantian modifier, dan release baru harus dilakukan pada fase
terpisah setelah scope-nya disetujui.

