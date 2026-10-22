# Ceyloro Platform macOS Product Scope

**Status:** Planning Only  
**Versi:** Draft 0.1  
**Sumber:** PRD Platform macOS Ceyloro dan referensi visual radial wheel  
**Platform:** macOS 13+  
**Arsitektur:** Intel `x86_64` dan Apple Silicon `arm64`  
**Hubungan:** Dokumen scope macOS; bukan pengganti PRD finalisasi macOS yang sudah dibuat sebelumnya.

## 1. Tujuan

Mendefinisikan pengalaman Ceyloro yang menyatu dengan Finder dan menu bar,
memakai radial wheel sebagai antarmuka utama, serta menerapkan katalog format
dan tools yang direncanakan pada Master Product Scope.

Dokumen ini hanya menyusun scope dan rencana. Implementasi aktual harus
melewati source audit, test, dan runtime verification.

## 2. Baseline yang perlu diverifikasi

- menu bar/accessory app;
- Shift-drag dari Finder;
- `Shift + Space` sebagai fallback;
- radial overlay;
- CoreGraphics, ImageIO, PDFKit, AVFoundation, dan FFmpeg;
- progress, cancellation, batch, dan cleanup;
- output folder dan kualitas;
- PDF merge;
- file actions dasar;
- universal build Intel dan Apple Silicon.

Semua item baseline berstatus Verify sampai pengujian membuktikannya.

## 3. Interaksi utama

### Convert formats

Modifier utama direncanakan untuk membuka wheel konversi. Petal berisi format
output yang valid untuk selection Finder saat itu.

### File tools

Modifier terpisah membuka wheel tools. Tools yang belum tersedia tidak boleh
jatuh diam-diam ke wheel actions atau tampil sebagai fitur aktif.

### File actions

Modifier terpisah membuka wheel actions. Operasi seperti Copy, Move, Copy Path,
Terminal, AirDrop, dan Float harus dibedakan dari conversion.

Pemetaan final antara Shift, Command, Option, dan Control masih menjadi
keputusan produk karena referensi visual dan implementasi baseline berbeda.

## 4. Finder dan lifecycle

Scope interaksi:

- file tunggal;
- multi-file;
- folder;
- drag dibatalkan;
- drop di luar wheel;
- Escape;
- `Shift + Space`;
- Accessibility permission;
- Automation permission;
- single-instance;
- launch at login;
- Settings dan Quit;
- cleanup saat shutdown.

Acceptance criteria:

- wheel hanya muncul dari drag atau shortcut yang valid;
- pasteboard drag lama tidak memicu wheel;
- drop di luar wheel tidak diteruskan ke Finder;
- overlay tidak menutup klik secara permanen;
- aplikasi dapat pulih setelah Settings atau progress ditutup;
- file sumber tidak berpindah tanpa tindakan eksplisit pengguna.

## 5. Radial wheel dan visual direction

Referensi menetapkan arah berikut:

- petal aktif oranye;
- petal lain netral;
- border abu-abu tipis;
- pusat wheel netral dengan label target;
- ikon garis untuk tools dan actions;
- label format singkat;
- wheel lebih ringan dan tidak terlalu besar;
- jumlah petal menyesuaikan konteks;
- posisi tidak melewati visible frame, Dock, atau menu bar.

Implementasi harus mendukung dark mode dengan warna sistem, Retina, keyboard
navigation, high contrast, dan accessibility label.

State yang wajib direncanakan:

- normal;
- hover/focus;
- probing/loading;
- disabled;
- configuration;
- processing;
- success;
- error;
- cancelled;
- empty.

## 6. Conversion scope macOS

### Images

Target scope: JPG, PNG, WebP, HEIC, TIFF, AVIF, BMP, PDF. SVG dapat menjadi
input-only bila capability engine mendukung.

Persyaratan:

- EXIF orientation;
- transparansi;
- flattening saat target tidak mendukung alpha;
- metadata;
- multi-page TIFF bila relevan;
- capability probe ImageIO/FFmpeg.

### Audio

Target scope: MP3, M4A, WAV, FLAC, OGG, OPUS, AIFF, WMA.

AVFoundation menjadi engine native bila tersedia, dengan FFmpeg sebagai jalur
tambahan. Target yang encoder-nya tidak tersedia harus disembunyikan.

### Video

Target scope: MP4, MOV, MKV, WebM, AVI, WMV, GIF, serta audio extraction.

Video conversion dan video-to-audio harus ditampilkan sebagai operasi berbeda.

### PDF

Scope awal: PDF ke JPG/PNG per halaman, TXT, DOCX best-effort, serta gambar ke
PDF dan PDF merge.

Scope lanjutan seperti PDF ke Pages, PPTX, XLSX, dan EPUB berstatus Proposed atau
Verify sampai engine dan fidelity-nya disetujui.

### Documents, slides, spreadsheets

Scope direncanakan:

- Documents: DOCX, Pages, Markdown, TXT, EPUB, HTML;
- Slides: PPT/PPTX ke PDF/JPG/PNG;
- Spreadsheets: XLS/XLSX, ODS, CSV, TSV, PDF.

Setiap hasil harus menjelaskan keterbatasan font, formula, layout, animation,
chart, embedded video, dan struktur multi-sheet atau multi-slide.

### Subtitles dan archives

- SRT, VTT, dan TXT sesuai operasi yang tersedia;
- ZIP, TAR, GZIP;
- Extract sebagai tool terpisah;
- RAR/7Z hanya ditawarkan setelah backend dan security review tersedia.

## 7. Tools scope macOS

### Prioritas awal

- Compress;
- Extract;
- PDF Split;
- PDF Organize;
- Image Crop;
- Image Add Background.

### Prioritas berikutnya

- Audio Trim;
- Audio Normalize;
- Video Trim;
- Video Snapshot;
- Video Mute;
- Metadata yang ruang lingkupnya jelas.

### Kandidat lanjutan

- Image Redact dan Annotate;
- Audio Bleep, Channels, dan Visualize;
- Video Crop, Speed, Split, Redact, dan Metadata;
- PDF Metadata;
- Float.

Tool yang membutuhkan parameter harus membuka konfigurasi. Misalnya Crop
membutuhkan area, Trim membutuhkan waktu, Split membutuhkan halaman atau titik
pemisah, dan Normalize membutuhkan metode yang dinyatakan.

## 8. File actions scope macOS

### Existing atau Verify

- Copy;
- Copy Path;
- Open in Terminal atau iTerm2;
- AirDrop.

### Placeholder atau Proposed

- Move;
- Float.

Move harus mencakup destination picker, konflik nama, izin, cross-volume,
cancel, rollback, dan perlindungan terhadap penghapusan sumber sebelum hasil
terkonfirmasi.

Float harus mencakup shelf, pin/unpin, multi-monitor, drag ulang ke aplikasi
lain, batas item, lifecycle saat quit, dan cleanup.

## 9. Output, job, dan Settings

Output:

- di samping file sumber atau folder kustom;
- nama unik saat bentrok;
- folder atau ZIP untuk hasil multi-page;
- tidak menimpa sumber;
- output parsial dibersihkan.

Job:

`queued → probing → running → succeeded / failed / cancelled`

Tambahkan `cancelling` bila backend membutuhkan waktu untuk berhenti.

Settings:

- output folder;
- kualitas JPG/HEIC;
- multi-page Folder/ZIP;
- launch at login;
- FFmpeg custom path;
- PDF merge preferences;
- modifier key bila sudah diputuskan;
- tool preferences bila tool sudah aktif.

## 10. QA scope

### Perangkat dan OS

- Mac Intel;
- Mac Apple Silicon;
- minimum macOS resmi;
- versi macOS terbaru yang ditargetkan.

### Interaksi

- Finder file tunggal, batch, folder, dan cancel;
- Accessibility diberikan, ditolak, dan dicabut;
- Automation diberikan dan ditolak;
- Dock, menu bar, multi-monitor, scaling, fullscreen;
- single-instance dan launch at login.

### Engine

- AVFoundation encoder tersedia dan tidak tersedia;
- FFmpeg bundled, custom, hilang, dan invalid;
- Pandoc/LibreOffice valid, hilang, dan gagal dijalankan;
- capability filtering.

### File safety

- konflik nama;
- folder read-only;
- disk penuh;
- file terkunci;
- Unicode dan path panjang;
- cancel saat antre, render, FFmpeg, document engine, dan archive.

## 11. Urutan pengerjaan yang direncanakan

1. MAC-0: freeze keputusan modifier, OS, engine, dan status baseline.
2. MAC-1: stabilkan Finder interaction dan lifecycle.
3. MAC-2: bangun state system dan visual radial wheel.
4. MAC-3: susun capability registry dan supported-formats catalog.
5. MAC-4: kerjakan tools prioritas awal.
6. MAC-5: kerjakan file actions yang sudah disetujui.
7. MAC-6: lengkapi conversion dan document scope yang feasible.
8. MAC-7: jalankan QA Intel/Apple Silicon dan release gate.

## 12. Definition of done

PRD macOS ini siap menjadi acuan implementasi ketika:

- modifier key dan minimum OS telah diputuskan;
- setiap format memiliki status dan capability source;
- Convert, Tools, dan Actions terpisah;
- placeholder tidak tampil sebagai fitur aktif;
- semua operasi memiliki output, error, cancel, dan cleanup criteria;
- visual direction referensi diterjemahkan ke design system yang accessible;
- QA matrix macOS disetujui;
- tidak ada klaim production sebelum release gate terpenuhi.

## 13. Status dokumen

Dokumen ini hanya PRD scope dan rencana. Ia tidak memulai implementasi, tidak
mengubah modifier, tidak mengaktifkan tools placeholder, dan tidak membuat
release baru.

