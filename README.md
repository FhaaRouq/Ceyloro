# Pomelo

Pomelo adalah prototipe native macOS menu-bar untuk mengubah file melalui satu gestur radial. Semua pemrosesan MVP berjalan lokal; file asli tidak pernah ditimpa.

## MVP yang tersedia

- Shift-drag file dari Finder untuk membuka roda di posisi kursor.
- Shift + Option atau Shift + Control membuka roda aksi yang tersedia.
- Konversi gambar ke JPG, PNG, HEIC, TIFF, atau PDF.
- Konversi PDF ke JPG/PNG per halaman atau TXT.
- Seleksi banyak file memakai irisan format yang valid.
- Antrean job dengan progres per file, pembatalan, folder/ZIP output multi-halaman, dan penamaan anti-timpa.
- Penggabungan beberapa gambar menjadi satu PDF dengan urutan dan opsi halaman yang bisa diatur.
- Menu bar, Pengaturan dasar, dan log lokal di `~/Library/Logs/Pomelo/app.log`.

## Build dan test

```sh
swift test
swift build -c release
```

`swift test` membutuhkan Xcode penuh karena test suite menggunakan XCTest. Jika mesin hanya memiliki Command Line Tools, gunakan `./scripts/check.sh`; skrip tersebut akan melewati XCTest dengan pesan yang jelas dan tetap memvalidasi build aplikasi.

Skrip build otomatis mencari Xcode di `/Applications` dan `~/Downloads`. Untuk menjalankan test secara langsung, gunakan path Xcode yang terpasang di mesinmu:

```sh
DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer swift test
```

Untuk menjalankan binary dari terminal:

```sh
.build/release/Pomelo
```

Distribusi publik masih membutuhkan app bundle universal, Developer ID signing, notarization, dan pengujian manual Shift-drag di Finder pada Intel serta Apple Silicon. Dukungan audio/video melalui ffmpeg dan tool lanjutan mengikuti fase berikutnya pada PRD.
