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
| W-19 | Diperbaiki sebagian | `Ceyloro.Windows.Tests` menjalankan pemeriksaan otomatis di Windows x64 untuk normalisasi target, deteksi/konversi TAR.GZ, TIFF multi-halaman, transparansi PNG/JPG, dan pembatalan. Ketujuh pemeriksaan lulus lokal dan di CI x64; CI juga membangun app ARM64, tetapi tes belum berjalan native pada ARM64. |
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

1. Build CI `win-x64` dan `win-arm64`, serta 7/7 pemeriksaan otomatis x64, lulus pada commit `8c7656cd`. Tes lokal x64 dengan .NET SDK 8.0.426 juga lulus 7/7.
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

## Tindak lanjut audit source code 22 Oktober 2026 — Windows saja

Sumber: `Audit_Ceyloro_Source_Code_Review_2026-10-22.docx`. Temuan khusus
macOS tidak diterapkan pada source Windows. Status di bawah membedakan perubahan
kode dari verifikasi yang tetap membutuhkan desktop/perangkat.

| Temuan | Status | Perubahan atau bukti |
| --- | --- | --- |
| W-1 hit-test sektor | Diperbaiki dan diuji | Hit-test memakai pusat sektor dan celah yang sama dengan geometri petal. Pemeriksaan mencakup pusat dan tepi sektor untuk 1–11 target, hub, dan luar roda. |
| W-2 area transparan | Perlu uji GUI Windows | Tidak diubah tanpa reproduksi karena penanganan area klik tembus bergantung pada perilaku window manager. Matriks manual mencakup petal, hub, transparansi, monitor ganda, dan drop di luar roda. |
| M-3 / M-6 probe saat drag | Diperbaiki pada jalur UI | Target dan validasi arsip/frame GIF dihitung pada worker. Explorer menerima `None` sampai hasil siap; validasi penuh arsip tetap berjalan di job konversi. |
| M-4 protokol FFmpeg | Diperketat; perlu uji format | Input dibatasi ke protokol `file`; argumen diuji agar whitelist diterapkan sebelum `-i`. Playlist dan input jaringan tidak didukung oleh kebijakan ini. Uji file media nyata tetap diperlukan dengan FFmpeg paket rilis. |
| M-5 GIF | Diperbaiki pada command builder | GIF memakai `palettegen`/`paletteuse`, 12 fps, dan lebar maksimum 720 px dengan rasio aspek terjaga. Output aktual 1080p/4K belum diverifikasi secara visual. |
| M-7 pesan batas ZIP | Diperbaiki dan diuji | Batas entri menyebut jumlah 100.000, terpisah dari batas ukuran ekstraksi 2 GB. |
| M-8 nama PDF multipage | Diselaraskan dan diuji pada fungsi penamaan | Windows mengikuti pola folder dan nama halaman macOS (`nama/nama-01.jpg`); konten render/ZIP perlu uji integrasi pada Windows. |
| M-9 cleanup temp | Diperbaiki dan diuji | Startup hanya menghapus direktori anak bernama GUID yang berumur lebih dari 24 jam; reparse point dan nama lain dilewati. |
| M-10 single instance | Diperbaiki pada startup | Mutex per user/session mencegah duplikat; peluncuran kedua mengirim pesan ke instance utama agar roda terbuka. Perlu smoke test desktop. |
| M-14 kualitas JPEG PDF | Diperbaiki dan diuji pada kebijakan kualitas | Kedua jalur JPEG PDF memakai encoder eksplisit: 85 untuk balanced dan 92 untuk original. Ukuran/visual output belum dibandingkan pada fixture PDF nyata. |
| M-15 konfirmasi keyboard | Affordance ambigu dihapus | Navigasi angka/panah dan nomor pada petal dihapus karena overlay tidak memiliki sumber file untuk menjalankan pilihan dengan Enter. Alur tetap drag-and-drop; Esc membatalkan. |
| M-16 Windows ARM64 | Belum dapat ditutup | Build ARM64 bukan bukti runtime. Smoke test pada perangkat Windows ARM64 tetap diperlukan. |
| M-17 signing | Belum ditandatangani | Workflow release Windows membuat dan menerbitkan SHA-256 untuk ZIP x64/ARM64. Authenticode memerlukan sertifikat penandatanganan yang tidak tersedia pada pekerjaan ini. |
| M-18 test GUI | Diperbaiki sebagian | Logika sektor dipisahkan sebagai fungsi murni dan masuk pemeriksaan otomatis. Drag/drop, DPI, monitor ganda, fokus, dan hit-test area transparan masih perlu matriks manual. |

Validasi lokal untuk perubahan ini: build `win-x64` berhasil dan 12/12
pemeriksaan Windows lulus. Restore menampilkan peringatan NU1900 karena sumber
data audit kerentanan NuGet tidak dapat dijangkau; tidak ada error build. Hasil
ini tidak menutup uji GUI, validasi FFmpeg output, Authenticode, atau runtime
ARM64.

