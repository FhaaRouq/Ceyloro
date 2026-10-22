# Ceyloro Master Product Scope

**Status:** Planning Only  
**Versi:** Draft 0.1  
**Sumber:** Master PRD Ceyloro dan referensi visual radial wheel  
**Hubungan:** Dokumen scope produk; bukan pengganti PRD finalisasi macOS, Windows, atau Linux yang sudah ada.

## 1. Tujuan dokumen

Dokumen ini mendefinisikan arah produk Ceyloro setelah MVP: konverter dan pusat
aksi file kontekstual yang menggunakan radial wheel sebagai pola interaksi
utama.

Dokumen ini hanya merencanakan scope, prioritas, kontrak, dan acceptance
criteria. Screenshot menjadi referensi desain dan cakupan, bukan bukti bahwa
fitur sudah tersedia di codebase.

## 2. Visi produk

Ceyloro membuat pekerjaan file yang berulang terasa singkat dan mudah diprediksi.
Pengguna memilih file dari file manager, membuka wheel, lalu memilih format,
tool, atau tindakan yang relevan tanpa harus membuka aplikasi besar yang
berbeda-beda.

Produk harus tetap:

- context-first: pilihan mengikuti file dan capability;
- radial-first: wheel menjadi pintu masuk utama;
- local-first: pemrosesan lokal;
- safe by default: sumber tidak ditimpa atau dihapus diam-diam;
- clear feedback: proses, hasil, dan kegagalan terlihat jelas;
- platform-aware: konsep konsisten, implementasi mengikuti OS.

## 3. Struktur pengalaman pengguna

### Convert formats

Petal menunjukkan format output, misalnya JPG, PNG, PDF, MP4, DOCX, ODS, atau
TAR. Hanya target yang kompatibel dengan seluruh input dan engine yang boleh
ditampilkan.

### File tools

Petal menunjukkan operasi pengolahan file, misalnya Compress, Crop, Metadata,
Split, Organize, dan Extract. Operasi dengan parameter membuka dialog
konfigurasi.

### File actions

Petal menunjukkan tindakan terhadap file atau lokasinya, misalnya Copy, Move,
Copy Path, Terminal, AirDrop, dan Float. File action tidak boleh dicampur dengan
format output.

## 4. Bahasa visual referensi

Rencana visual yang akan menjadi acuan:

- dasar putih atau abu-abu sangat muda;
- border tipis berwarna abu-abu;
- petal aktif berwarna oranye;
- petal nonaktif berwarna netral;
- ikon garis sederhana untuk tools dan actions;
- label pendek dengan kontras tinggi;
- pusat wheel menampilkan target aktif;
- ukuran wheel menyesuaikan jumlah pilihan dan ruang layar;
- state loading, disabled, success, error, dan cancelled dirancang eksplisit.

Implementasi akhir tetap harus mendukung dark mode dan accessibility. Referensi
tidak diperlakukan sebagai spesifikasi pixel-perfect.

## 5. Katalog format yang direncanakan

Katalog harus membedakan input, output, input-only, output-only, engine, dan
batasan fidelity.

| Kategori | Format yang direncanakan | Catatan |
|---|---|---|
| Images | JPG, PNG, WebP, HEIC, TIFF, AVIF, BMP, PDF | SVG direncanakan sebagai input-only bila engine mendukung |
| Audio | MP3, M4A, WAV, FLAC, OGG, OPUS, AIFF, WMA | Codec dan encoder harus diprobe |
| Video | MP4, MOV, MKV, WebM, AVI, WMV, GIF | Audio extraction dipisahkan dari video conversion |
| PDF | DOCX, Pages, PPTX, XLSX, JPG, PNG, EPUB, TXT, MD | Sebagian target berstatus Proposed/Verify |
| Documents | DOCX, Pages, Markdown, TXT, EPUB, HTML | Layout kompleks diberi batasan fidelity |
| Slides | PPT/PPTX, PDF, JPG, PNG | Animasi, font, dan video tertanam perlu dijelaskan |
| Spreadsheets | XLS/XLSX, ODS, CSV, TSV, PDF | Formula dan formatting mungkin tidak seluruhnya dipertahankan |
| Subtitles | SRT, VTT, TXT | TXT tidak mempertahankan timestamp |
| Archives | ZIP, TAR, GZIP | RAR input-only sampai backend extraction disetujui |

Daftar ini adalah target scope, bukan klaim dukungan release saat ini.

## 6. Katalog tools yang direncanakan

### Image tools

- Compress;
- Redact;
- Metadata;
- Edit;
- Annotate;
- Add Background;
- Crop.

### Audio tools

- Compress;
- Bleep;
- Metadata;
- Normalize;
- Visualize;
- Trim;
- Channels.

### Video tools

- Compress;
- Redact;
- Metadata;
- Mute;
- Trim;
- Crop;
- Speed;
- Snapshot;
- Split.

### PDF tools

- Compress;
- Organize;
- Metadata;
- Split.

### Archive tools

- Extract.

### File actions

- Copy;
- Move;
- Copy Path;
- Terminal;
- AirDrop;
- Float.

Tool tidak boleh tampil sebagai fitur aktif sebelum input, output, parameter,
error handling, cancellation, dan hasilnya didefinisikan.

## 7. Capability registry

Registry menjadi satu sumber kebenaran untuk wheel dan dokumentasi. Setiap
capability minimal memiliki:

- kategori operasi;
- format input;
- format output atau tool;
- platform;
- engine dan versi;
- dukungan single-file, batch, atau multi-page;
- opsi dan parameter;
- dukungan progress dan cancellation;
- batasan fidelity;
- status probing;
- error code dan pesan pengguna.

UI tidak boleh menampilkan format hanya karena ekstensi tersebut tercantum di
README.

## 8. Kontrak job dan output

Setiap job memiliki `jobId`, input, operasi, target, options, status, progress,
output, error, dan timestamps.

Status yang direncanakan:

`queued → probing → running → succeeded / failed / cancelled`

`cancelling` dapat dipakai saat engine memerlukan waktu untuk berhenti.

Aturan output:

- sumber tidak diubah, dihapus, atau ditimpa;
- konflik nama menghasilkan nama unik;
- output multi-page memiliki aturan folder atau ZIP;
- batch tetap lanjut ketika satu item gagal;
- output parsial dibersihkan atau diberi status jelas;
- hasil akhir menunjukkan lokasi output;
- folder output tidak boleh dipilih secara diam-diam.

## 9. Pengaturan produk

Pengaturan yang masuk scope:

- output di samping sumber atau folder kustom;
- kualitas per kategori bila tersedia;
- hasil multi-page Folder atau ZIP;
- launch at login;
- engine path kustom;
- konfirmasi PDF merge;
- modifier key;
- urutan dan visibility petal;
- favorit dan preset;
- workflow tersimpan;
- batch behavior.

Setiap setting harus memiliki default, penjelasan dampak, dan perilaku yang
konsisten setelah relaunch.

## 10. Prioritas roadmap produk

### P0 — Stabilitas

Audit findings, gesture, overlay, output safety, cancel, cleanup, error
handling, capability filtering, build, dan release.

### P1 — Core workflow

Conversion yang sudah ada, file actions dasar, output, progress, Settings, dan
dokumentasi format yang akurat.

### P2 — Workflow produktivitas

Batch lanjutan, preset, archive extraction, PDF tools, image tools terpilih,
dan multi-page workflow.

### P3 — Advanced tools

Audio/video/image/PDF tools lanjutan, Float, dan platform parity.

### P4 — Monetisasi dan polish

Free/Premium, entitlement, workflow customization, onboarding, dan UX lanjutan.

## 11. Free dan Premium

Pembagian belum dikunci sebelum scope stabil. Prinsipnya:

- Free harus cukup berguna untuk memahami nilai produk.
- Premium menjual efisiensi, preset, customization, dan workflow lanjutan.
- Fitur dasar tidak boleh sengaja dibuat rusak.
- Entitlement tidak boleh mengganggu conversion offline.
- Lisensi harus menjelaskan aktivasi, transfer perangkat, update, dan major
  upgrade.

## 12. Non-functional requirements

- wheel responsif dan tidak menunggu conversion untuk dirender;
- job tidak membuat aplikasi utama hang;
- proses eksternal menerima argumen aman;
- sumber file selalu aman;
- log tidak menyimpan data sensitif yang tidak perlu;
- keyboard navigation dan accessibility dipertimbangkan;
- platform dan arsitektur dinyatakan eksplisit;
- dependency dan engine dapat didiagnosis;
- dokumentasi mengikuti release yang benar.

## 13. Kriteria penerimaan global

Fitur baru hanya dianggap selesai jika:

- status dan requirement terdokumentasi;
- capability engine sesuai dengan target yang ditawarkan;
- input valid menghasilkan output valid;
- input invalid menghasilkan error yang jelas;
- konflik nama aman;
- sumber tetap utuh;
- cancel dan cleanup bekerja;
- state UI relevan tersedia;
- automated test dan smoke test lulus;
- batasan fidelity didokumentasikan.

Test minimum mencakup file valid, file rusak, batch, konflik nama, folder
read-only, file terkunci, cancellation, engine hilang, file besar, nama Unicode,
dan multi-monitor untuk operasi UI terkait.

## 14. Keputusan yang harus dibuat sebelum implementasi

- minimum OS per platform;
- modifier key per mode;
- tools release pertama;
- format input/output final per platform;
- engine dokumen, presentasi, spreadsheet, dan PDF;
- dukungan multi-file per operasi;
- batasan fidelity;
- Free/Premium;
- lisensi dan aktivasi;
- status Float;
- status batch lanjutan.

## 15. Definition of done dokumen

Master Product Scope siap menjadi acuan implementasi ketika status setiap fitur,
prioritas, capability contract, job contract, dan acceptance criteria telah
disetujui. Dokumen ini tidak memulai pengerjaan source code secara otomatis.

