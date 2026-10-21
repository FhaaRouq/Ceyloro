# Ceyloro — Fase 2: Media

Fase 1 dianggap selesai dari sisi implementasi dan automated test. Gate manual PRD
tetap perlu dijalankan di Finder pada macOS 13–15, Intel, dan Apple Silicon.

## Ruang lingkup

- Konversi audio dengan AVFoundation sebagai engine native.
- Konversi video dengan AVFoundation/VideoToolbox bila tersedia.
- FFmpeg LGPL universal sebagai fallback untuk format yang tidak ditangani native.
- Deteksi engine saat runtime; target yang tidak tersedia tidak ditampilkan di roda.
- Subtitle SRT/VTT ke TXT dan antar-format subtitle yang didukung.
- Arsip ZIP, TAR, GZIP, dan RAR baca-saja sesuai engine yang tersedia.
- Progres per file, pembatalan, cleanup temp, dan laporan kegagalan per file tetap memakai JobRunner.

## Urutan implementasi

1. Tambah model format audio/video/subtitle/arsip dan matriks target yang dapat dites.
2. Tambah capability probe untuk AVFoundation dan FFmpeg tanpa akses jaringan.
3. Tambah bridge proses eksternal FFmpeg dengan parsing progres dan pembatalan aman.
4. Implementasikan audio native lalu video native/fallback.
5. Implementasikan parser dan converter subtitle.
6. Implementasikan operasi arsip serta test keselamatan file.
7. Integrasikan target yang tersedia ke roda dan Settings jalur engine.
8. Uji matriks sampel di Intel dan Apple Silicon, kemudian dokumentasikan hasilnya.

## Aturan Fase 2

- File asli tidak pernah diubah, dihapus, atau ditimpa.
- Semua pemrosesan tetap lokal dan offline.
- Tidak ada sektor roda untuk engine yang tidak tersedia.
- Setiap perubahan kecil dibuat sebagai commit terpisah dan dipush ke `main`.
- Setiap tahap harus lulus `swift test` dan build universal sebelum lanjut.

## Gate keluar

- Matriks audio/video/subtitle/arsip lulus pada sampel kecil di Intel dan ARM.
- Job dapat dibatalkan tanpa proses anak, file parsial, atau folder temp tersisa.
- Hasil yang berhasil ditampilkan di Finder dan kegagalan dilaporkan per file.
- FFmpeg yang dibundel memiliki build LGPL universal, checksum, atribusi, dan skrip build yang dapat diulang.
