# Ceyloro Windows audit — status remediasi

Tanggal: 21 Oktober 2026
Sumber: `Ceyloro-Windows-Audit.docx`
Lingkup: shell Windows, backend konversi, pengaturan, UI, CI, dan paket x64/ARM64.

## Hasil

Temuan W-01–W-22 sudah ditinjau satu per satu, lalu audit lanjutan menambahkan
W-23–W-25 untuk penanganan format dan TIFF multi-halaman. Perbaikan source
dikerjakan pada PR Windows. Build lokal tidak dapat dilakukan karena .NET
SDK/MSBuild tidak tersedia. GitHub Actions lulus untuk `win-x64` dan
`win-arm64` pada commit `81b43c39`; CI memeriksa kompilasi, bukan konversi atau
UI ketika aplikasi berjalan.

| ID | Status | Penanganan |
| --- | --- | --- |
| W-01 | Perlu validasi Windows | DragEnter/DragOver/DragDrop, jumlah file, ekstensi, target, dan empty state dicatat di log lokal `%LocalAppData%\Ceyloro\Logs\app.log`. Reproduksi apakah Explorer memicu event tetap perlu dilakukan di Windows. |
| W-02 | Diperbaiki | Overlay memberi instruksi dan teks status, bukan hub gelap kosong. |
| W-03 | Backend ditambahkan; perlu validasi Windows | Ada PDF→JPG/PNG/TXT, gambar→PDF, dan PDF multi-halaman ke folder/ZIP; PDF teks yang dipindai menjelaskan bahwa OCR diperlukan. |
| W-04 | Diperbaiki; perlu validasi Windows | `ffprobe` memasok durasi, FFmpeg `out_time_ms` memperbarui progres, dan progress bar memakai marquee bila durasi tidak diketahui. |
| W-05 | Diperbaiki; perlu validasi Windows | Proses FFmpeg dihentikan dan output parsial dibersihkan pada kegagalan atau pembatalan. File sumber tidak dihapus. |
| W-06 | Diperbaiki | Proses dimulai sebelum callback pembatalan didaftarkan; token diperiksa sesudah start. |
| W-07 | Diperbaiki sebagian | Dukungan subtitle, arsip ZIP/TAR/TAR.GZ, PDF, dan matriks Windows didokumentasikan. RAR/7Z dan OCR tetap tidak ditawarkan. |
| W-08 | Diperbaiki sebagian | Format yang tidak dikenal menampilkan alasan. Identifikasi masih berdasarkan ekstensi; file dengan ekstensi yang salah gagal dengan pesan backend. |
| W-09 | Diperbaiki | Roda memeriksa encoder dan muxer yang tersedia pada FFmpeg lokal sebelum menampilkan target media. |
| W-10 | Diperbaiki | Target `gzip` secara eksplisit menghasilkan TAR.GZ; dokumentasi menyebut TAR.GZ. |
| W-11 | Diperbaiki sebagian | Pengaturan memeriksa direktori output dapat ditulis dan binary FFmpeg dapat dijalankan. Belum ada dialog untuk menguji setiap encoder sebelum menyimpan. |
| W-12 | Diperbaiki | Empty state membedakan file kosong/tidak terbaca, format tidak dikenal, dan FFmpeg yang hilang atau gagal dijalankan. |
| W-13 | Diperbaiki sebagian | Tooltip tray dan instruksi overlay menjelaskan `Ctrl+Alt+Space`; hotkey alternatif yang dapat diatur dan onboarding satu kali belum tersedia. |
| W-14 | Diperbaiki sebagian | Angka di luar jumlah pilihan tidak memilih target lain; tombol panah mengubah pilihan. Roda belum membagi daftar panjang ke beberapa tingkat. |
| W-15 | Perlu validasi Windows | Form memakai batas virtual desktop dan koordinat pointer layar; pengujian multi-monitor, skala campuran, fullscreen, dan drop pada area transparan tetap diperlukan. |
| W-16 | Diperbaiki; perlu validasi Windows | Manifest menyatakan DPI-aware PerMonitorV2. Perilaku scaling tetap perlu diuji pada perangkat. |
| W-17 | Diperbaiki | Form progres menampilkan nama file; ringkasan memuat kegagalan per file dan menawarkan membuka folder output. |
| W-18 | Diperbaiki sebagian | Ikon tray Ceyloro dibuat khusus; roda mendukung navigasi panah dan teks target tetap terlihat. High-contrast dan aksesibilitas perlu diperiksa langsung di Windows. |
| W-19 | Belum selesai | CI membangun x64 dan ARM64, tetapi belum ada test project Windows atau tes otomatis yang dijalankan. |
| W-20 | Diperbaiki; perlu validasi Windows | Target framework Windows 10 2004/API 19041; workflow build dan release membuat paket terpisah `win-x64` dan `win-arm64`. Kelayakan runtime kedua arsitektur masih harus diuji. |
| W-21 | Belum selesai untuk distribusi publik | Paket tetap ZIP dan belum code-signed/installer. README memperingatkan pengguna tentang SmartScreen. |
| W-22 | Diperbaiki | Pengaturan rusak disalin sebagai backup, default dimuat, dan pengguna diberi pesan serta log lokal. |
| W-23 | Diperbaiki di PR Windows berikutnya | `.gz` didukung sebagai arsip hanya jika isinya TAR; stream gzip biasa tidak ditawarkan. `.tar.gz` dan `.tgz` juga dipetakan ke target TAR.GZ. |
| W-24 | Diperbaiki; perlu validasi Windows | WEBP, HEIC, dan AVIF disiapkan dengan FFmpeg ke PNG sebelum masuk backend PDF atau konversi JPG/PNG/TIFF. PNG menjaga transparansi sampai backend menentukan hasil akhir. Target hanya ditawarkan bila FFmpeg lokal memiliki encoder PNG dan decoder gambar terkait. |
| W-25 | Diperbaiki; perlu validasi Windows | TIFF multi-halaman dibaca per halaman dan seluruh halaman dikeluarkan sebagai koleksi seperti di macOS. Konversi gambar Windows memakai GDI+ untuk JPG/PNG/TIFF; JPG meratakan transparansi ke latar putih. |

## Fitur Windows yang masuk dalam remediasi

- Konversi media memakai capability map dari FFmpeg yang dipilih atau dibundel;
  kualitas JPG/HEIC dan progres batch tersedia.
- SRT/VTT dapat diubah di antara kedua format dan diekspor menjadi teks biasa.
- ZIP, TAR, dan TAR.GZ dapat saling dikonversi. Ekstraksi memblokir path traversal,
  symlink dan tipe khusus, lebih dari 100.000 entri, serta data hasil ekstraksi
  di atas 2 GB.
- PDF dapat dirender ke JPG/PNG atau diekstrak teksnya; satu atau beberapa gambar
  dapat dijadikan PDF dengan pilihan halaman, margin, kualitas, urutan, dan mode
  gabungan/per gambar.
- Release Windows mengambil FFmpeg dan FFprobe LGPL terverifikasi untuk x64 dan
  ARM64 serta menghasilkan ZIP per arsitektur.

## Validasi yang masih diperlukan sebelum menyatakan rilis lulus

1. Build CI `win-x64` dan `win-arm64` lulus pada commit parity `81b43c39`.
2. Pada Windows x64 dan ARM64, uji overlay dan Explorer drag-drop pada PNG, MP4,
   MP3, PDF, SRT, serta file tidak dikenal.
3. Uji konversi representatif, termasuk TIFF multi-halaman dan gambar-ke-PDF untuk semua format yang ditawarkan,
   PDF multi-halaman folder/ZIP, arsip rusak dan
   path berbahaya, batch campuran, direktori output read-only, pembatalan, dan
   jalur Unicode/panjang.
4. Uji dua monitor dengan koordinat negatif, DPI campuran, high-contrast,
   keyboard, serta Windows fullscreen.
5. Putuskan kebutuhan test project, code signing, installer, onboarding, dan
   hotkey alternatif sebelum rilis publik.

Audit statis source selesai untuk lingkup yang disebutkan, tetapi status lulus
operasional belum dapat diberikan tanpa pengujian langsung pada Windows x64
serta ARM64. CI saat ini tidak memiliki test project Windows; signing dan
installer juga tetap menjadi pekerjaan distribusi sebelum rilis publik.

