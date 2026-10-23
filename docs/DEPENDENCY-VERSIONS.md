# Versi Dependensi Build Ceyloro

Dokumen ini mencatat versi eksplisit semua dependensi build yang digunakan di
proyek ini. Perbarui dokumen ini setiap kali ada upgrade versi.

---

## macOS

| Komponen | Versi | Catatan |
|---|---|---|
| Xcode | 16.x | Default pada runner `macos-15` di GitHub Actions |
| Swift | bundled dengan Xcode 16.x | Lihat `Package.swift` untuk deployment target |
| macOS deployment target | 13.0 | Didefinisikan di `Package.swift`: `.macOS(.v13)` |
| FFmpeg (macOS universal) | 7.1.1 | LGPL-only, dibangun dari source via `scripts/build-ffmpeg-universal.sh` |
| libshine | 3.1.1 | Fixed-point MP3 encoder, dibangun bersama FFmpeg |
| LibreOffice | _tidak dibundel di CI_ | Dipasang secara lokal jika diperlukan; lihat `docs/FFMPEG.md` |
| Pandoc | _tidak dibundel di CI_ | Dipasang secara lokal jika diperlukan |

### Cara memperbarui FFmpeg macOS

1. Ubah `VERSION` di `scripts/build-ffmpeg-universal.sh` ke versi baru.
2. Jalankan script: `./scripts/build-ffmpeg-universal.sh`
3. Catat SHA-256 baru dari output script.
4. Perbarui variabel `FFMPEG_SHA256_ARM64` dan `FFMPEG_SHA256_X86_64` di
   `scripts/build-ffmpeg-universal.sh` (lihat task C3).
5. Perbarui tabel di atas.

---

## Windows

| Komponen | Versi | Catatan |
|---|---|---|
| .NET SDK | 10.0.100 | Dikunci via `Windows/global.json`; `rollForward: latestPatch` |
| Target framework | net10.0-windows10.0.19041.0 | Didefinisikan di `Ceyloro.Windows.csproj` |
| PdfPig | 0.1.16 | NuGet package; dikunci via `packages.lock.json` |
| FFmpeg (Windows x64) | autobuild-2026-10-20-13-08 `N-127790-g56dbd4cd37` | LGPL, diunduh via `scripts/fetch-ffmpeg-windows.ps1` |
| FFmpeg (Windows arm64) | autobuild-2026-10-20-13-08 `N-127790-g56dbd4cd37` | LGPL, diunduh via `scripts/fetch-ffmpeg-windows.ps1` |
| Source: BtbN/FFmpeg-Builds | `autobuild-2026-10-20-13-08` | Lihat `scripts/fetch-ffmpeg-windows.ps1` |

### Cara memperbarui FFmpeg Windows

1. Cek release terbaru di https://github.com/BtbN/FFmpeg-Builds/releases
2. Pilih tag `autobuild-*` yang sesuai dan catat `Build` hash-nya.
3. Unduh arsip x64 dan arm64 secara manual, hitung SHA-256 masing-masing.
4. Perbarui variabel `$Release`, `$Build`, dan `$expectedByArchitecture` di
   `scripts/fetch-ffmpeg-windows.ps1`.
5. Perbarui tabel di atas.

---

## Catatan umum

- Perubahan versi dependensi yang mempengaruhi reproducibility build harus
  di-review dan di-commit bersama perubahan kode yang memerlukannya.
- Lock file (`packages.lock.json` untuk .NET, `global.json` untuk SDK) harus
  di-commit ke repository dan tidak boleh digenerate ulang tanpa alasan yang jelas.
- Untuk audit SHA-256 FFmpeg macOS, lihat task C3 di `.kiro/specs/audit-remediation/tasks.md`.
