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
- [x] Binary FFmpeg dan FFprobe Windows x64/ARM64 untuk paket release: LGPL, dipin ke build tertentu, dan diverifikasi dengan SHA-256 sebelum dipaketkan.
- [x] Video → audio di planner portable dan shell Windows.
- [x] Workflow paket release macOS universal dan Windows self-contained untuk x64/ARM64 dengan FFmpeg yang sesuai arsitektur.
- [ ] Installer, auto-update, dan code signing Windows; item ini membutuhkan tool installer, sertifikat, dan kredensial distribusi eksternal.

## Status shell Windows awal

Proyek shell berada di `Windows/Ceyloro.Windows`. Ia sengaja terpisah dari
target AppKit macOS dan memakai WinForms .NET 8. Shell ini mencakup konversi
media melalui FFmpeg, subtitle SRT/VTT, arsip ZIP/TAR/TAR.GZ, serta PDF melalui
backend Windows/PdfPig dan penulis PDF lokal. Paket release mengambil FFmpeg dan
FFprobe LGPL yang dipin untuk tiap arsitektur dan memverifikasi checksum sebelum
membuat ZIP terpisah. Fitur baru dan paket ARM64 masih menunggu build CI serta
validasi runtime pada perangkat Windows.

Integrasi Explorer yang otomatis membuka roda saat drag dimulai, installer,
auto-update, dan code signing tetap menjadi pekerjaan distribusi/parity
lanjutan. Fitur kompresi media bukan bagian Fase 3 dan akan direncanakan sebagai
fase terpisah. Rincian status tiap temuan audit Windows ada di
[`docs/WINDOWS-AUDIT-REMEDIATION.md`](WINDOWS-AUDIT-REMEDIATION.md).

Build portable product di macOS:

```sh
swift build --product CeyloroEngine
```

Pada Windows, target yang sama dapat dibangun dengan Swift for Windows tanpa
membawa target UI macOS ke dalam proses build. Port UI Windows dimulai setelah
kontrak engine ini stabil.
