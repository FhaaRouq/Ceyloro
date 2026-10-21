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

Shell Windows ditargetkan untuk x64 dan ARM64. Paket release dibuat terpisah
untuk tiap arsitektur dan menyertakan FFmpeg serta FFprobe yang sesuai.
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
| ZIP, TAR, TAR.GZ | ZIP, TAR, TAR.GZ |

Selain itu, JPG, PNG, TIFF, BMP, dan GIF dapat dijadikan PDF; satu atau beberapa gambar
dapat digabung menjadi PDF. WEBP, HEIC, dan AVIF belum ditawarkan untuk PDF karena
backend Windows saat ini tidak dapat membacanya secara andal. PDF multi-halaman dapat
disimpan sebagai folder atau ZIP. RAR/7Z, OCR untuk PDF hasil
scan, serta format yang tidak didukung encoder lokal tidak ditawarkan.

Jika Windows SmartScreen muncul saat pertama kali membuka aplikasi, pilih
**More info**, lalu **Run anyway** hanya untuk paket yang diunduh dari GitHub
Release resmi Ceyloro.

