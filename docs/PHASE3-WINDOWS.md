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
- [ ] Binary FFmpeg Windows x64.
- [ ] Installer, auto-update, dan code signing Windows.

## Status shell Windows awal

Proyek shell berada di `Windows/Ceyloro.Windows`. Ia sengaja terpisah dari
target AppKit macOS dan memakai WinForms bawaan .NET 8, sehingga dapat dibangun
di Windows tanpa menambah paket NuGet. Alur pertama sudah mencakup konversi
media melalui FFmpeg, dengan output unik dan laporan per file. PDF native,
integrasi Explorer yang otomatis membuka roda saat drag dimulai, installer, dan
code signing menjadi pekerjaan lanjutan setelah build Windows pertama tervalidasi
di CI.

Build portable product di macOS:

```sh
swift build --product CeyloroEngine
```

Pada Windows, target yang sama dapat dibangun dengan Swift for Windows tanpa
membawa target UI macOS ke dalam proses build. Port UI Windows dimulai setelah
kontrak engine ini stabil.
