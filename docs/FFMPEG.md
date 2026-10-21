# FFmpeg untuk Ceyloro

Ceyloro tidak mengunduh binary dan tidak membutuhkan FFmpeg agar fitur native tetap berjalan.

Untuk mengaktifkan format media tambahan, sediakan satu binary FFmpeg executable yang sudah dibangun untuk `x86_64` dan `arm64`, dengan konfigurasi LGPL yang sesuai distribusinya.

## Verifikasi lokal

Letakkan binary sebagai `Sources/Ceyloro/Resources/ffmpeg`, lalu jalankan:

```sh
./scripts/verify-ffmpeg.sh
./scripts/build-app.sh
```

Atau gunakan lokasi lain tanpa menyalin binary ke repository:

```sh
CEYLORO_FFMPEG_PATH=/path/to/ffmpeg ./scripts/build-app.sh
```

Build script akan menyalin binary ke `Ceyloro.app/Contents/Resources/ffmpeg`. Saat aplikasi berjalan, Ceyloro hanya menawarkan target FFmpeg jika binary tersebut executable dan terdeteksi.

Untuk distribusi publik, sertakan teks lisensi LGPL FFmpeg, atribusi, konfigurasi build, dan checksum binary yang benar-benar dipakai pada release.
