# Ceyloro

> Konverter file lokal yang bekerja dari menu bar—pilih file, arahkan ke format tujuan, selesai.

[![Preview release](https://img.shields.io/github/v/release/Neural-Operations-Digital-Engineering/Ceyloro?display_name=tag&sort=semver&include_prereleases)](https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/releases)
[![Windows build](https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/actions/workflows/windows-shell.yml/badge.svg)](https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/actions/workflows/windows-shell.yml)
[![macOS CI](https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/actions/workflows/macos-ci.yml/badge.svg)](https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/actions/workflows/macos-ci.yml)
[![License](https://img.shields.io/badge/core-MIT-2f855a.svg)](LICENSE)

Ceyloro dirancang untuk satu hal: membuat konversi file terasa sesingkat mungkin. Di macOS, cukup tahan `Shift` sambil menarik file dari Finder. Roda konversi muncul di posisi kursor dan menampilkan format yang tersedia untuk file tersebut.

Semua pemrosesan berjalan lokal. File asli tidak diubah, ditimpa, atau diunggah ke server.

## Download

| Platform | Paket | Checksum |
| --- | --- | --- |
| macOS Universal (Intel + Apple Silicon) | [Download Ceyloro untuk macOS](https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/releases/latest) | Bawaan bundle |
| Windows x64 | [Download Ceyloro untuk Windows x64](https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/releases/latest) | [.sha256](https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/releases/latest) |
| Windows ARM64 | [Download Ceyloro untuk Windows ARM64](https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/releases/latest) | [.sha256](https://github.com/Neural-Operations-Digital-Engineering/Ceyloro/releases/latest) |

Paket di atas adalah release build mandiri (self-contained). Build macOS bersifat universal (`x86_64` + `arm64`) dan menyertakan biner FFmpeg universal. Paket Windows bersifat self-contained (tidak memerlukan instalasi .NET terpisah), membawa biner `ffmpeg.exe` dan `ffprobe.exe` resmi yang sesuai arsitektur, serta dilengkapi file verifikasi checksum SHA-256 (`.sha256`).

### Membuka aplikasi preview

Paket preview belum ditandatangani secara resmi.

- **macOS:** buka aplikasi sekali dengan klik kanan **Open**. Jika macOS tetap
  memblokirnya, buka **System Settings › Privacy & Security**, gulir ke bagian
  keamanan, lalu pilih **Open Anyway** untuk Ceyloro. Setelah itu konfirmasi
  **Open**.
- **Windows:** jika SmartScreen muncul, pilih **More info**, lalu **Run anyway**
  hanya jika paket diunduh dari halaman Release resmi Ceyloro.

## Cara menggunakan

### macOS

1. Unduh dan buka `Ceyloro-macOS-universal.zip`.
2. Pindahkan `Ceyloro.app` ke folder Applications.
3. Jalankan Ceyloro; ikon akan muncul di menu bar.
4. Di Finder, tahan `Shift` lalu tarik satu atau beberapa file.
5. Lepaskan file pada format tujuan di roda.

Untuk membuka roda tanpa drag (fallback), pilih satu atau beberapa file di Finder lalu tekan **`Shift + Spasi`**. Tekan `Esc` atau lepaskan file di luar area target untuk membatalkan.

#### Izin macOS (First-Run)
- **Aksesibilitas (Accessibility)**: Diperlukan agar Ceyloro dapat mendeteksi gestur kursor Shift-drag global dan hotkey `Shift + Spasi`. Prompt sistem akan muncul otomatis saat pertama kali dibuka.
- **Otomatisasi (Automation)**: Diperlukan saat menggunakan shortcut `Shift + Spasi` agar Ceyloro dapat membaca file yang sedang dipilih di Finder melalui Apple Events. Jika belum diizinkan, Ceyloro akan menampilkan notifikasi pengingat dengan tombol langsung ke Pengaturan Sistem.

### Windows

1. Unduh dan ekstrak `Ceyloro-Windows-x64.zip`.
2. Jalankan `Ceyloro.exe`.
3. Tekan `Ctrl + Alt + Space` untuk membuka roda.
4. Tarik file dari Explorer ke roda, lalu lepaskan pada format tujuan.

Paket Windows yang sudah terbit adalah preview x64. Workflow rilis saat ini menyiapkan paket
terpisah untuk x64 dan ARM64; paket untuk kode terbaru baru terbit setelah tag rilis dibuat.
Shell Windows menggunakan hotkey untuk membuka roda terlebih dahulu; gestur menahan `Shift`
sambil menarik file dari Finder belum tersedia di Windows.

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

- **Pemrosesan Offline Penuh**: Semua konversi diproses secara lokal di perangkat Anda tanpa transmisi jaringan atau telemetri.
- **Integritas File Sumber**: File sumber tidak pernah diubah, dihapus, atau ditimpa.
- **Proteksi Penamaan Anti-Timpa**: File tujuan diberi nama unik menggunakan reservasi atomik tingkat kernel (`O_CREAT | O_EXCL`) untuk mencegah tabrakan berkas antar-proses.
- **Pembersihan File Sementara**: Seluruh staging konversi diisolasi dalam subdirektori sementara (`Ceyloro-...`) dan langsung dihapus saat konversi berhasil, dibatalkan, gagal, atau saat aplikasi ditutup.
- **Sanitasi Log**: Log aplikasi hanya disimpan lokal di `~/Library/Logs/Ceyloro/app.log`, path pengguna disamarkan (`~`), dan berkas log dirotasi otomatis saat mencapai 1 MB.
- **Pelaporan Batch Transparan**: Konversi banyak file melaporkan status keberhasilan dan kegagalan per file secara independen tanpa menghentikan berkas lainnya.

## Status platform

| Platform | Status | Catatan |
| --- | --- | --- |
| macOS Intel | Preview | App universal, target macOS 13+ |
| macOS Apple Silicon | Preview | App universal, target macOS 13+ |
| Windows x64 + ARM64 | Preview | CI membangun kedua arsitektur; paket resmi bergantung pada tag rilis berikutnya |

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
./scripts/check.sh --universal
./scripts/build-app.sh
```

Jika Xcode tidak berada di lokasi standar:

```sh
DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer swift test
```

### Windows

Kebutuhan:

- Windows x64 atau ARM64;
- Visual Studio 2022 dengan workload **.NET desktop development**;
- .NET 8 SDK.

Build shell Windows:

```powershell
# Build x64 dan ARM64
dotnet build Windows/Ceyloro.Windows/Ceyloro.Windows.csproj -c Release -r win-x64
dotnet build Windows/Ceyloro.Windows/Ceyloro.Windows.csproj -c Release -r win-arm64

# Jalankan unit & integration tests Windows
dotnet run --project Windows/Ceyloro.Windows.Tests/Ceyloro.Windows.Tests.csproj -c Release -r win-x64
```

Workflow GitHub Actions membangun shell Windows untuk x64 dan ARM64 setiap ada perubahan terkait Windows. Workflow rilis membuat paket desktop untuk kedua arsitektur pada setiap tag `v*`.

## Arsitektur

Ceyloro menggunakan pendekatan open-core:

- `CeyloroCore` berisi logika yang dapat diuji—format, hit-testing, penamaan output, job runner, dan aturan konversi.
- `CeyloroEngine` berisi kontrak engine lintas-platform.
- Shell macOS menggunakan AppKit, ImageIO, PDFKit, AVFoundation, dan FFmpeg.
- Shell Windows menggunakan WinForms dan FFmpeg.

Komponen proyek memiliki batas lisensi berikut:

| Komponen | Lisensi | Catatan |
| --- | --- | --- |
| `CeyloroCore` | MIT | Logika format, hit-testing, penamaan, job runner, dan kebijakan konversi |
| `CeyloroEngine` | MIT | Kontrak engine lintas-platform |
| `Sources/Ceyloro/` | Proprietary | App macOS, UI, menu bar, branding, dan integrasi desktop |
| `Windows/` | Proprietary | Shell Windows, UI, tray, dan integrasi desktop |
| FFmpeg/libshine | Lisensi pihak ketiga | Mengikuti lisensi dan notice masing-masing komponen |

Kode app terlihat di repo agar build dan audit dapat dilakukan, tetapi visibilitas
source tidak berarti izin redistribusi. Lihat [LICENSE](LICENSE) dan
[LICENSE-APP.md](LICENSE-APP.md) sebelum menggunakan komponen proprietary.

## Roadmap

- installer dan auto-update untuk Windows;
- code signing dan notarization untuk distribusi publik;
- parity fitur penuh antara shell macOS dan Windows;
- opsi komersial dan fitur premium.

## Kontribusi dan laporan masalah

Bug report dan usulan fitur dapat dibuat melalui [GitHub Issues](https://github.com/neuraldigital/Ceyloro/issues). Sertakan platform, versi Ceyloro, format sumber, format tujuan, dan langkah reproduksi jika memungkinkan.

## Lisensi

`CeyloroCore` dan `CeyloroEngine` dilisensikan di bawah [MIT License](LICENSE).
App Ceyloro, shell Windows, dan komponen proprietary lainnya mengikuti
[ketentuan terpisah](LICENSE-APP.md). FFmpeg dan libshine mengikuti lisensi
distribusinya sendiri.

