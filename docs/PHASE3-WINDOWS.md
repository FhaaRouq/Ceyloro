# Ceyloro — Fase 3: Windows dan engine lintas-platform

Fase 3 dimulai dengan memisahkan kontrak engine dari shell desktop. Target baru
`CeyloroEngine` hanya memakai Foundation dan tidak mengimpor AppKit, SwiftUI,
AVFoundation, CoreGraphics, atau WinRT. Library ini menjadi tempat planner,
capability, request, dan kontrak backend yang dipakai kedua platform.

## Pembagian tanggung jawab

- `CeyloroEngine`: aturan format, capability, pemilihan backend, request, dan job contract.
- Shell macOS: menu bar, Finder drag-and-drop, radial overlay, AVFoundation, dan PDF/ImageIO.
- Shell Windows: system tray, Explorer drag-and-drop, overlay, Settings, dan Windows media APIs.
- FFmpeg: backend fallback lintas-platform untuk format yang tidak tersedia native.

## Status tahap pertama

- [x] Target `CeyloroEngine` Foundation-only.
- [x] Deteksi format tanpa UniformTypeIdentifiers.
- [x] Planner dapat memilih native atau FFmpeg berdasarkan capability.
- [x] Test capability Windows dan pemilihan backend.
- [x] Shell Windows awal: system tray, hotkey, overlay radial, drag-and-drop Explorer, Settings, progres, pembatalan, dan batch FFmpeg.
- [x] Binary FFmpeg Windows x64 untuk paket release: LGPL, dipin ke build tertentu, dan diverifikasi dengan SHA-256 sebelum dipaketkan.
- [x] Video → audio di planner portable dan shell Windows.
- [x] Paket release macOS universal dan Windows self-contained dengan FFmpeg yang sudah tersedia.
- [ ] Installer, auto-update, dan code signing Windows; item ini membutuhkan tool installer, sertifikat, dan kredensial distribusi eksternal.

## Status shell Windows awal

Proyek shell berada di `Windows/Ceyloro.Windows`. Ia sengaja terpisah dari
target AppKit macOS dan memakai WinForms bawaan .NET 8, sehingga dapat dibangun
di Windows tanpa menambah paket NuGet. Shell ini mencakup konversi media melalui
FFmpeg, termasuk video → audio, output unik, progres, pembatalan, dan laporan per
file. Paket release mengambil binary FFmpeg LGPL yang dipin dan memverifikasi
checksum-nya sebelum membuat ZIP.

PDF native Windows, integrasi Explorer yang otomatis membuka roda saat drag
dimulai, installer, auto-update, dan code signing tetap menjadi pekerjaan
distribusi/parity lanjutan. Fitur kompresi media bukan bagian Fase 3 dan akan
direncanakan sebagai fase terpisah.

Build portable product di macOS:

```sh
swift build --product CeyloroEngine
```

Pada Windows, target yang sama dapat dibangun dengan Swift for Windows tanpa
membawa target UI macOS ke dalam proses build. Port UI Windows dimulai setelah
kontrak engine ini stabil.
