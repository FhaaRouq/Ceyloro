# FFmpeg LGPL yang dibundel

Ceyloro menggunakan FFmpeg sebagai proses terpisah untuk format media yang
tidak ditangani AVFoundation. Binary yang dipakai untuk build lokal dibuat dari
source resmi FFmpeg dengan konfigurasi berikut:

- FFmpeg 7.1.1
- `--disable-gpl`
- `--disable-nonfree`
- static, x86_64 + arm64
- minimum macOS 13.0
- native LGPL encoders untuk MP3, Vorbis, Opus, MPEG-4, VP9, WMV, dan GIF;
  tidak menggunakan `libx264`, `libmp3lame`, `libvorbis`, atau `libopus`

Source resmi:

`https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz`

Bangun ulang binary dengan:

```sh
DEVELOPER_DIR=/Users/vhaenzz-/Downloads/Xcode.app/Contents/Developer \
./scripts/build-ffmpeg-universal.sh
```

Verifikasi yang wajib dilakukan sebelum rilis:

```sh
./scripts/verify-ffmpeg.sh
shasum -a 256 Sources/Ceyloro/Resources/ffmpeg
```

Binary `Sources/Ceyloro/Resources/ffmpeg` sengaja tidak dimasukkan ke Git.
Untuk distribusi publik, sertakan source corresponding FFmpeg, teks LGPL
v2.1+, konfigurasi build, checksum binary, dan pemberitahuan komponen pihak
ketiga yang benar-benar dipakai.
