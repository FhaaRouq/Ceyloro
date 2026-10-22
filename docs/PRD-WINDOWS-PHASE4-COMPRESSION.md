# PRD Windows — Fase 4: Tools Kompresi

**Produk:** Ceyloro untuk Windows  
**Status:** Panduan implementasi dan verifikasi lokal  
**Target awal:** Windows x64  
**Target berikutnya:** Windows ARM64 setelah validasi runtime dan dependensi selesai

## 1. Ringkasan

Ceyloro Windows adalah shell desktop yang menyediakan alur drag-and-drop berbasis roda radial untuk mengonversi dan mengompres file. Dokumen ini khusus untuk pekerjaan Windows pada Fase 4. Implementasi dasar fitur kompresi sudah berada di branch main; pekerjaan di Windows IDE berfokus pada build, pengujian, penyempurnaan UX, dan validasi terhadap file nyata.

Alur pengguna:

1. Tarik file dari File Explorer.
2. Buka roda dengan gesture atau hotkey.
3. Pilih **Kompres**.
4. Ceyloro membuat hasil baru tanpa mengubah file asli.
5. Pengguna melihat progres per file dan ringkasan hasilnya.

## 2. Tujuan dan non-tujuan

### Tujuan

- Menyediakan kompresi lokal dan offline untuk gambar, audio, video, PDF, dan dokumen umum.
- Menjaga file sumber tetap utuh.
- Menangani batch: satu file gagal tidak menghentikan file lain.
- Menyediakan pembatalan, progres, nama output unik, serta pembersihan file sementara.
- Menyembunyikan aksi **Kompres** jika tipe file atau encoder yang diperlukan tidak tersedia.
- Menjadi dasar yang dapat diuji di Windows x64 dan kemudian Windows ARM64.

### Tidak termasuk dalam PRD ini

- OCR, penghapusan metadata, atau kompresi semantik dokumen Office.
- Kompresi arsip yang sudah ada seperti ZIP/RAR/7Z.
- Pengeditan video, pemotongan durasi, subtitle, atau ekstraksi frame sebagai workflow tersendiri.
- Sinkronisasi cloud atau upload file.
- Code signing, installer production, dan distribusi Microsoft Store.

## 3. Jenis file yang didukung

| Kelompok | Ekstensi | Perilaku kompresi |
|---|---|---|
| Gambar | .jpg, .png, .tiff | Encode ulang ke format yang sama dengan kualitas lebih rendah atau ukuran lebih efisien. |
| Gambar melalui FFmpeg | .gif, .webp, .heic, .avif | Hanya tampil bila FFmpeg dapat membaca dan menulis format tersebut. |
| Audio | .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff | Encode ulang ke ekstensi yang sama menggunakan profil kompresi FFmpeg. |
| Video | .mp4, .mov, .mkv, .webm, .avi, .wmv | Encode ulang ke ekstensi yang sama menggunakan profil kompresi FFmpeg. |
| PDF | .pdf | Render halaman lalu bangun PDF baru dengan ukuran gambar lebih rendah. Selectable text dapat berubah menjadi raster. |
| Dokumen umum | .doc, .docx, .rtf, .txt, .md, .pages, .xls, .xlsx, .ppt, .pptx | Dikemas menjadi satu ZIP yang berisi file asli. Ini bukan optimasi isi dokumen. |

Ukuran hasil tidak selalu lebih kecil, terutama untuk file yang sudah terkompresi. Aplikasi tetap harus menyelesaikan proses dengan aman dan memberi tahu pengguna.

## 4. Perilaku produk

### Pemicu

- Gesture utama: tahan Shift sambil menarik file dari Explorer jika gesture tersebut tersedia pada build Windows.
- Fallback: Ctrl + Alt + Space membuka roda secara manual, kemudian file ditarik ke overlay.
- Jika kemampuan belum selesai diperiksa, roda menampilkan status **Memeriksa format…**.
- Jika FFmpeg diperlukan tetapi tidak tersedia, target terkait tidak ditampilkan dan pesan harus menjelaskan bahwa FFmpeg belum ditemukan.

### Output

- File asli tidak pernah diubah, dihapus, atau ditimpa.
- Nama default media: nama-file (terkompres).ext.
- Nama default dokumen: nama-file (terkompres).zip.
- Jika nama sudah ada, gunakan nama unik seperti nama-file (terkompres) 2.ext.
- Output ditulis ke folder output yang dipilih pengguna.
- Proses menggunakan folder sementara yang unik, lalu memindahkan hasil final setelah selesai.
- File sementara dan output parsial dihapus saat selesai, gagal, atau dibatalkan.

### Batch

- Setiap file memiliki status sendiri.
- Kegagalan satu file tidak membatalkan file lainnya.
- Ringkasan membedakan jumlah berhasil, gagal, dan dibatalkan.
- Untuk kegagalan, tampilkan nama file dan pesan yang dapat ditindaklanjuti.

### Progres dan pembatalan

- Tampilkan nama file yang sedang diproses.
- Tampilkan progres total batch dan, bila tersedia, progres file aktif.
- Tombol **Batal** menghentikan proses berikutnya dan menghentikan FFmpeg yang sedang berjalan.
- Pembatalan tidak boleh meninggalkan output final atau folder sementara.
- Menutup jendela progres diperlakukan sebagai pembatalan, atau jendela tidak boleh menyediakan tombol tutup yang memberi kesan pekerjaan berhenti padahal masih berjalan.

## 5. Arsitektur yang diharapkan

Gunakan struktur yang sudah ada:

- Windows/Ceyloro.Windows/ConversionEngine.cs — orkestrasi konversi, kompresi, progres, dan laporan batch.
- Windows/Ceyloro.Windows/PortableRules.cs — deteksi jenis file dan daftar target.
- Windows/Ceyloro.Windows/FfmpegCommandBuilder.cs — perintah FFmpeg dan profil audio/video.
- Windows/Ceyloro.Windows/FfmpegCapabilities.cs — probing encoder/decoder.
- Windows/Ceyloro.Windows/WindowsImageConverter.cs — jalur gambar native Windows.
- Windows/Ceyloro.Windows/PdfConversion.cs — render dan pembangunan ulang PDF.
- Windows/Ceyloro.Windows/RadialOverlayForm.cs — roda, drag/drop, pilihan aksi, progres, dan pembatalan.
- Windows/Ceyloro.Windows/SettingsStore.cs — folder output dan preferensi pengguna.
- Windows/Ceyloro.Windows.Tests/Program.cs — smoke test executable.

Logika deteksi format, penamaan output, keputusan capability, dan kebijakan kompresi sebaiknya tetap tidak bergantung pada form.

## 6. Prasyarat di Windows

Siapkan secara manual:

1. Windows 10 2004 atau lebih baru, atau Windows 11.
2. Visual Studio 2022 dengan workload **.NET desktop development**, atau Rider/VS Code dengan .NET SDK.
3. .NET 8 SDK.
4. FFmpeg dan FFprobe build Windows yang dapat didistribusikan bersama aplikasi.
5. Untuk ARM64, perangkat/VM Windows ARM64 dan binary FFmpeg ARM64 yang sesuai. Build x64 tidak otomatis membuktikan dukungan ARM64.

> Binary FFmpeg tidak dianggap tersedia hanya karena kode Ceyloro ada di GitHub. Paket rilis harus membawa ffmpeg.exe dan ffprobe.exe, atau menyediakan instruksi path yang jelas.

## 7. Menjalankan dari IDE

### Visual Studio

1. Buka folder repository atau solution Windows.
2. Jadikan Ceyloro.Windows sebagai startup project.
3. Pilih konfigurasi Release dan target win-x64.
4. Pastikan ffmpeg.exe dan ffprobe.exe dapat ditemukan aplikasi.
5. Jalankan aplikasi dan uji drag dari File Explorer.
6. Jalankan project Ceyloro.Windows.Tests sebagai executable test harness.

### PowerShell

Jalankan dari root repository:

~~~powershell
dotnet restore .\Windows\Ceyloro.Windows\Ceyloro.Windows.csproj
dotnet build .\Windows\Ceyloro.Windows\Ceyloro.Windows.csproj -c Release -r win-x64
dotnet build .\Windows\Ceyloro.Windows.Tests\Ceyloro.Windows.Tests.csproj -c Release -r win-x64
dotnet run --project .\Windows\Ceyloro.Windows.Tests\Ceyloro.Windows.Tests.csproj -c Release -r win-x64
~~~

Setelah x64 lulus, ulangi build dengan -r win-arm64 pada mesin yang mendukung runtime dan dependency ARM64.

## 8. Matriks uji manual

### Dasar

- [ ] JPG menghasilkan JPG baru dengan suffix (terkompres).
- [ ] PNG dan TIFF single-page menghasilkan file dengan ekstensi yang sama.
- [ ] PDF beberapa halaman menghasilkan PDF baru dan jumlah halaman tetap sama.
- [ ] DOCX menghasilkan ZIP yang berisi dokumen sumber.
- [ ] MP4, MOV, MP3, M4A, OGG, OPUS, dan WAV menampilkan **Kompres** bila capability FFmpeg tersedia.
- [ ] Format yang tidak dapat dibaca/ditulis FFmpeg tidak menampilkan target kompresi.

### Ketahanan

- [ ] Dua input dengan nama sama tidak menimpa hasil; nama kedua mendapat nomor unik.
- [ ] Batch berisi satu file rusak tetap menyelesaikan file valid lainnya.
- [ ] Ringkasan menampilkan file gagal dan alasannya.
- [ ] Pembatalan saat encoding berlangsung menghentikan proses dan tidak meninggalkan output parsial.
- [ ] Pembatalan saat file masih antre memperbarui status menjadi dibatalkan.
- [ ] Menjalankan dua batch tidak membuat tombol Batal mengendalikan job yang salah.
- [ ] Folder temp Ceyloro tidak menumpuk setelah job selesai atau dibatalkan.

### UX Windows

- [ ] Ctrl + Alt + Space membuka roda di monitor yang sedang aktif.
- [ ] Roda tidak tertutup taskbar atau area kerja yang tidak dapat dipakai.
- [ ] Label menggunakan bahasa Indonesia yang konsisten.
- [ ] Folder output dapat diubah dan hasil berikutnya masuk ke folder tersebut.
- [ ] Jika FFmpeg hilang, pengguna mendapat pesan yang jelas dan jalur native tetap dapat dipakai.
- [ ] SmartScreen ditangani melalui instruksi README, bukan dengan mematikan proteksi sistem.

## 9. Kriteria penerimaan

Fase 4 Windows siap untuk uji pengguna jika:

- Build Release win-x64 berhasil dari IDE dan PowerShell.
- Test harness Windows selesai tanpa kegagalan.
- Kompresi gambar, audio, video, PDF, dan dokumen berjalan sesuai tabel dukungan.
- File asli tidak berubah.
- Nama bentrok, pembatalan, progres, kegagalan sebagian, dan pembersihan temp terverifikasi.
- Target FFmpeg yang tidak didukung tidak ditawarkan.
- Paket uji menyertakan binary FFmpeg atau instruksi path yang dapat diikuti.
- README tidak menyebut Windows sebagai parity penuh sebelum gesture, arsitektur, FFmpeg, signing, dan pengujian manual benar-benar setara.

## 10. Batasan yang perlu dicatat

- Build Windows awal menargetkan x64; ARM64 membutuhkan validasi terpisah.
- PDF dikompres melalui rasterisasi sehingga selectable text dan beberapa metadata PDF dapat hilang.
- Dokumen Office saat ini dikemas sebagai ZIP; ini bukan kompresi internal isi dokumen.
- Ukuran hasil tidak selalu lebih kecil.
- Aplikasi yang belum ditandatangani dapat memicu Microsoft Defender SmartScreen. Instruksi pengguna harus menyebut **More info → Run anyway** hanya setelah sumber paket dipastikan benar.
- Dukungan codec bergantung pada capability FFmpeg yang terpasang, bukan sekadar ekstensi file.

## 11. Laporan validasi

Setelah pengujian Windows, catat:

- Versi Windows dan arsitektur CPU.
- Versi .NET SDK.
- Versi/varian FFmpeg dan FFprobe.
- Format yang lolos dan format yang disembunyikan.
- Ukuran sebelum/sesudah untuk minimal satu gambar, audio, video, PDF, dan dokumen.
- Hasil pembatalan, bentrok nama, batch sebagian gagal, dan pembersihan temp.
- Apakah gesture Shift dan hotkey fallback bekerja.
- Bug yang hanya terjadi pada x64 atau ARM64.
