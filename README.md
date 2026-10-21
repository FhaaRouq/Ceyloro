# Ceyloro

> Konverter file lokal yang bekerja dari menu bar—pilih file, arahkan ke format tujuan, selesai.

[![Preview release](https://img.shields.io/github/v/release/neuraldigital/Ceyloro?display_name=tag&sort=semver&include_prereleases)](https://github.com/neuraldigital/Ceyloro/releases)
[![Windows build](https://github.com/neuraldigital/Ceyloro/actions/workflows/windows-shell.yml/badge.svg)](https://github.com/neuraldigital/Ceyloro/actions/workflows/windows-shell.yml)
[![License](https://img.shields.io/badge/core-MIT-2f855a.svg)](LICENSE)

Ceyloro dirancang untuk satu hal: membuat konversi file terasa sesingkat mungkin. Di macOS, cukup tahan `Shift` sambil menarik file dari Finder. Roda konversi muncul di posisi kursor dan menampilkan format yang tersedia untuk file tersebut.

Semua pemrosesan berjalan lokal. File asli tidak diubah, ditimpa, atau diunggah ke server.

## Download

| Platform | Paket |
| --- | --- |
| macOS Intel + Apple Silicon | [Download Ceyloro untuk macOS](https://github.com/neuraldigital/Ceyloro/releases/download/v0.1.0-preview.3/Ceyloro-macOS-universal.zip) |
| Windows x64 | [Download Ceyloro untuk Windows](https://github.com/neuraldigital/Ceyloro/releases/download/v0.1.0-preview.3/Ceyloro-Windows-x64.zip) |

Paket di atas adalah preview release. Build macOS sudah universal (`x86_64` + `arm64`), sedangkan paket Windows bersifat self-contained dan tidak memerlukan instalasi .NET.

## Cara menggunakan

### macOS

1. Unduh dan buka `Ceyloro-macOS-universal.zip`.
2. Pindahkan `Ceyloro.app` ke folder Applications.
3. Jalankan Ceyloro; ikon akan muncul di menu bar.
4. Di Finder, tahan `Shift` lalu tarik satu atau beberapa file.
5. Lepaskan file pada format tujuan di roda.

Untuk membuka roda tanpa drag, gunakan hotkey cadangan yang dikonfigurasi di aplikasi. Tekan `Esc` atau lepaskan file di luar area target untuk membatalkan.

### Windows

1. Unduh dan ekstrak `Ceyloro-Windows-x64.zip`.
2. Jalankan `Ceyloro.exe`.
3. Tekan `Ctrl + Alt + Space` untuk membuka roda.
4. Tarik file dari Explorer ke roda, lalu lepaskan pada format tujuan.

Paket release Windows sudah membawa FFmpeg LGPL yang sudah diverifikasi. Untuk build dari source, letakkan `ffmpeg.exe` LGPL di samping `Ceyloro.exe` atau pilih lokasinya melalui menu **Pengaturan**.

## Yang bisa dilakukan

| Jenis file | Format tujuan |
| --- | --- |
| Gambar | JPG, PNG, HEIC, TIFF, PDF |
| PDF | JPG, PNG per halaman, TXT untuk PDF yang berisi teks |
| Audio | MP3, M4A, WAV, FLAC, OGG, OPUS, AIFF |
| Video | MP4, MOV, MKV, WebM, AVI, WMV, GIF, MP3, M4A, WAV, FLAC, OGG, OPUS, AIFF |
| Subtitle | SRT, VTT |
| Arsip | ZIP, TAR, TAR.GZ |

Format yang tidak tersedia pada sistem atau backend konversi akan disembunyikan dari roda. Dukungan format dapat berbeda antara macOS dan Windows.

Fitur lain yang tersedia:

- konversi batch dengan hasil per file;
- batch tetap berjalan ketika salah satu file gagal;
- output multi-halaman sebagai folder atau ZIP;
- penggabungan beberapa gambar menjadi satu PDF;
- pengaturan kualitas dan folder output;
- progres, pembatalan, serta penamaan output anti-timpa;
- navigasi roda menggunakan keyboard dan angka `1`–`9`.

## Privasi dan keamanan file

- Pemrosesan dilakukan secara offline di perangkat pengguna.
- File sumber tidak pernah diubah, dihapus, atau ditimpa.
- File hasil diberi nama unik jika nama tujuan sudah ada.
- Konversi batch melaporkan keberhasilan dan kegagalan secara terpisah.
- File sementara dibersihkan setelah pekerjaan selesai atau dibatalkan.

## Status platform

| Platform | Status | Catatan |
| --- | --- | --- |
| macOS Intel | Preview | App universal, target macOS 13+ |
| macOS Apple Silicon | Preview | App universal, target macOS 13+ |
| Windows x64 | Preview | Shell tray + radial drag-and-drop |

Paket preview belum melalui Apple notarization atau Windows code signing. Sistem operasi dapat menampilkan peringatan keamanan saat pertama kali aplikasi dibuka.

## Pengembangan

### macOS

Kebutuhan:

- macOS 13 atau lebih baru;
- Xcode penuh;
- Swift 5.9 atau lebih baru.

Build dan test:

```sh
swift test
swift build -c release
./scripts/build-app.sh
```

Jika Xcode tidak berada di lokasi standar:

```sh
DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer swift test
```

### Windows

Kebutuhan:

- Windows x64;
- Visual Studio 2022 dengan workload **.NET desktop development**;
- .NET 8 SDK.

Build shell Windows:

```powershell
dotnet build Windows/Ceyloro.Windows/Ceyloro.Windows.csproj -c Release
```

Workflow GitHub Actions membangun shell Windows setiap ada perubahan terkait Windows dan membuat paket desktop pada setiap tag `v*`.

## Arsitektur

Ceyloro menggunakan pendekatan open-core:

- `CeyloroCore` berisi logika yang dapat diuji—format, hit-testing, penamaan output, job runner, dan aturan konversi.
- `CeyloroEngine` berisi kontrak engine lintas-platform.
- Shell macOS menggunakan AppKit, ImageIO, PDFKit, AVFoundation, dan FFmpeg.
- Shell Windows menggunakan WinForms dan FFmpeg.

Target `CeyloroCore` tersedia di bawah MIT. Aplikasi, UI, branding, integrasi desktop, dan fitur komersial tetap proprietary. Lihat [LICENSE](LICENSE) untuk detailnya.

## Roadmap

- installer dan auto-update untuk Windows;
- code signing dan notarization untuk distribusi publik;
- parity fitur penuh antara shell macOS dan Windows;
- opsi komersial dan fitur premium.

## Kontribusi dan laporan masalah

Bug report dan usulan fitur dapat dibuat melalui [GitHub Issues](https://github.com/neuraldigital/Ceyloro/issues). Sertakan platform, versi Ceyloro, format sumber, format tujuan, dan langkah reproduksi jika memungkinkan.

## Lisensi

Kode `CeyloroCore` dilisensikan di bawah [MIT License](LICENSE). App Ceyloro dan komponen proprietary lainnya memiliki ketentuan lisensi terpisah. FFmpeg, jika digunakan, mengikuti lisensi distribusinya sendiri.
