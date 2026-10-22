# Ceyloro Windows shell

Shell Windows Ceyloro memakai WinForms .NET 8 dan PdfPig untuk membaca teks PDF.
Paket release resmi menyertakan dependensi aplikasi dan binary media yang
sesuai arsitektur. Shell ini menyediakan:

- ikon system tray;
- hotkey `Ctrl+Alt+Space` untuk membuka roda;
- drag-and-drop file dari Explorer ke overlay;
- target format yang disaring dari jenis file yang dipilih;
- konversi batch berbasis FFmpeg, dengan progres, pembatalan, output unik, dan
  laporan kegagalan per file;
- kompresi gambar, audio, video, PDF, dan dokumen umum;
- Settings untuk folder output dan lokasi `ffmpeg.exe`.

## Build di Windows

Pasang Visual Studio 2022 dengan workload **.NET desktop development**, lalu:

```powershell
dotnet build .\Windows\Ceyloro.Windows\Ceyloro.Windows.csproj -c Release -r win-x64
dotnet build .\Windows\Ceyloro.Windows\Ceyloro.Windows.csproj -c Release -r win-arm64
```

Paket release resmi sudah membawa `ffmpeg.exe` build LGPL di samping `Ceyloro.exe`.
Build dari source tree tidak membawa binary itu; letakkan `ffmpeg.exe` build LGPL
di samping executable atau pilih file tersebut melalui menu **Pengaturan**.

Alur penggunaan saat ini: jalankan Ceyloro, tekan `Ctrl+Alt+Space`, lalu tarik
file dari Explorer ke roda dan lepaskan pada target yang diinginkan. `Esc`
membatalkan overlay.

Untuk membuka roda langsung saat pengujian manual, jalankan `Ceyloro.exe --show`.
Jika Ceyloro sudah berjalan di system tray, peluncuran kedua akan mengaktifkan
roda pada instance yang sudah terbuka.

Shell Windows ditargetkan untuk x64 dan ARM64. Paket release dibuat terpisah
untuk tiap arsitektur dan menyertakan FFmpeg serta FFprobe yang sesuai.

Target `Kompres` muncul sebagai pilihan pertama pada roda. Media dikodekan ulang
dengan ukuran lebih kecil, PDF dirender ulang, dan dokumen umum dikemas sebagai
ZIP agar file asli tetap utuh.
Gestur `Shift` sambil menarik file belum tersedia di Windows; alur Windows
menggunakan hotkey untuk membuka roda terlebih dahulu.

## Format Windows

Roda hanya menampilkan target yang didukung encoder/muxer FFmpeg yang dipilih
atau dibundel.

| Sumber | Target Windows |
| --- | --- |
| JPG, PNG, TIFF, BMP, GIF | JPG, PNG, HEIC, TIFF, PDF |
| WEBP, HEIC, AVIF | JPG, PNG, HEIC, TIFF |
| PDF | JPG, PNG, TXT untuk PDF yang memiliki teks |
| MP3, M4A, WAV, FLAC, OGG, OPUS, AIFF, WMA | MP3, M4A, WAV, FLAC, OGG, OPUS, AIFF |
| MP4, MOV, MKV, WEBM, AVI, WMV | MP4, MOV, MKV, WEBM, AVI, WMV, GIF, serta target audio yang tersedia |
| GIF animasi | Target video dan audio yang tersedia |
| SRT, VTT | SRT, VTT, TXT |
| ZIP, TAR, TAR.GZ | ZIP, TAR, TAR.GZ (termasuk `.tgz` dan `.gz` yang berisi TAR) |

Selain itu, JPG, PNG, TIFF, BMP, dan GIF dapat dijadikan PDF; satu atau beberapa gambar
dapat digabung menjadi PDF. WEBP, HEIC, dan AVIF juga dapat dijadikan PDF jika FFmpeg
yang tersedia dapat membaca format sumber tersebut. PDF multi-halaman dapat
disimpan sebagai folder atau ZIP. RAR/7Z, OCR untuk PDF hasil
scan, serta format yang tidak didukung encoder lokal tidak ditawarkan.

Konversi JPG, PNG, TIFF, BMP, dan GIF memakai decoder gambar Windows. TIFF multi-halaman
menghasilkan satu file per halaman, seperti alur macOS. WEBP, HEIC, dan AVIF memakai FFmpeg
untuk membuat PNG perantara; ini menjaga transparansi saat target akhirnya JPG, PNG, TIFF,
atau PDF.

## Distribusi & Code Signing (Authenticode)

Paket rilis resmi didistribusikan sebagai arsip ZIP mandiri per arsitektur (`win-x64` dan `win-arm64`). Untuk rilis publik produksi:

1. **Authenticode Signing**:
   Gunakan sertifikat penandatanganan kode yang valid dengan `signtool.exe`:
   ```powershell
   signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /f "SertifikatCeyloro.pfx" /p "Password" "bin\Release\net8.0-windows10.0.19041.0\win-x64\publish\Ceyloro.exe"
   ```
2. **SmartScreen & Reputasi**:
   Build rilis preview tanpa sertifikat EV berpotensi memicu peringatan Windows Defender SmartScreen. Pengguna dapat memilih **More info** -> **Run anyway** untuk file yang diunduh dari rilis resmi GitHub. Release Windows menyertakan file SHA-256 (`.sha256`) untuk memeriksa integritas unduhan.
3. **Verifikasi Checksum**:
   Setiap rilis GitHub menyertakan `SHA256SUMS.txt` / `.sha256` untuk memastikan integritas biner sebelum dijalankan:
   ```powershell
   Get-FileHash -Algorithm SHA256 .\Ceyloro-Windows-x64.zip
   ```

## Verifikasi Perangkat Nyata Windows ARM64

Build target `win-arm64` dikompilasi secara cross-compile via .NET SDK pada GitHub Actions. Untuk validasi perangkat fisik Windows on ARM (seperti Snapdragon X Elite/Copilot+ PC):

- [ ] **Overlay Launch**: Hotkey `Ctrl+Alt+Space` membuka roda radial tanpa artefak grafis GDI+/WinForms.
- [ ] **Radial Hit-Testing**: Verifikasi `RadialGeometry.HitTest` pada layar sentuh dan mouse/trackpad presisi tinggi.
- [ ] **FFmpeg Native ARM64**: Pastikan biner `ffmpeg.exe` arm64 yang dibundel mengeksekusi kompresi video/audio tanpa emulasi x64.
- [ ] **PDF Rendering**: Uji konversi halaman PDF via WinRT API pada Windows 11 ARM64.
- [ ] **Archive & Temp**: Pastikan ekstraksi ZIP/TAR dan pembersihan temp folder berjalan normal.

Jika Windows SmartScreen muncul saat pertama kali membuka aplikasi, pilih
**More info**, lalu **Run anyway** hanya untuk paket yang diunduh dari GitHub
Release resmi Ceyloro.
