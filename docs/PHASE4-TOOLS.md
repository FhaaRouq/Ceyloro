# Ceyloro — Fase 4: Tools dan kompresi

Fase 4 menambahkan operasi yang tidak mengubah format utama file. Fitur pertama
adalah **Kompres**, tersedia di macOS dan Windows dengan hasil baru, progress,
pembatalan, penamaan unik, dan pembersihan staging.

## Status

- [x] Kebijakan kompresi lintas-platform di `CeyloroCore`.
- [x] Gambar: JPG, PNG, HEIC, dan TIFF memakai format sumber.
- [x] Audio: re-encode bitrate lebih ringan melalui FFmpeg.
- [x] Video: re-encode kualitas lebih ringan melalui FFmpeg.
- [x] PDF: render ulang halaman dengan preset seimbang.
- [x] Dokumen umum: DOC, DOCX, RTF, TXT, MD, Pages, XLS/XLSX, dan PPT/PPTX
      dikemas menjadi ZIP tanpa mengubah file sumber.
- [x] Progress per file, pembatalan, laporan kegagalan per file, output folder,
      nama bentrok, dan cleanup file sementara memakai infrastruktur job yang
      sudah ada.
- [x] Item `Kompres` di mode Tools macOS dan roda Windows.
- [ ] Preset kualitas yang dapat dipilih langsung dari UI.
- [ ] Kompresi semantik dokumen Office/PDF yang mempertahankan seluruh struktur
      internal tanpa rasterisasi atau pengarsipan.

## Perilaku format dokumen

PDF dikompres dengan merender ulang halaman pada resolusi dan kualitas seimbang;
PDF hasilnya dapat kehilangan lapisan teks yang dapat dipilih. Dokumen Office,
RTF, TXT, Markdown, dan Pages dikemas sebagai ZIP sehingga isinya tetap utuh,
tetapi penghematan ukuran bergantung pada apakah file sumber sudah memakai
kompresi internal. File sumber tidak pernah ditimpa.

## Verifikasi manual

1. Tarik JPG, MP4, MP3, PDF, dan DOCX ke roda.
2. Pilih `Kompres`.
3. Pastikan hasil memakai nama `nama-terkompres.*` atau `nama-terkompres.zip`.
4. Ulangi konversi untuk memastikan nama menjadi `... 2.*`, bukan menimpa hasil.
5. Batalkan saat progress berjalan dan pastikan tidak ada file parsial.
6. Untuk PDF, periksa jumlah halaman dan buka ZIP dokumen untuk memastikan file
   asli berada di dalamnya.
