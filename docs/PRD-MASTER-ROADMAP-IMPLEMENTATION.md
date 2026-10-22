# PRD Master Roadmap Implementasi Ceyloro

**Status:** Planning Only  
**Versi:** Draft 0.1  
**Sumber:** Master Product Requirements Document Ceyloro dan referensi desain radial wheel  
**Ruang lingkup:** perencanaan produk lintas-platform macOS, Windows, dan Linux  
**Catatan:** Dokumen ini hanya mendefinisikan rencana. Tidak ada requirement di sini yang dianggap sudah diimplementasikan hanya karena muncul pada screenshot.

## 1. Ringkasan

Ceyloro diarahkan menjadi pusat aksi file kontekstual: pengguna memilih file,
membuka radial wheel, lalu memilih konversi, tools, atau file action yang
relevan. Master PRD ini menerjemahkan arah tersebut menjadi roadmap yang dapat
dikerjakan secara bertahap dan dapat diverifikasi.

Fokus utamanya adalah menjaga tiga hal tetap konsisten di semua platform:

1. pilihan yang muncul harus sesuai dengan kapabilitas nyata;
2. file sumber selalu aman;
3. setiap operasi memiliki feedback, pembatalan, dan hasil yang jelas.

## 2. Masalah yang hendak diselesaikan

Pengguna harus berpindah-pindah aplikasi untuk mengonversi gambar, audio,
video, PDF, dokumen, spreadsheet, presentasi, atau arsip. Operasi seperti
compress, extract, crop, trim, copy path, dan move juga memiliki alur yang
terpisah.

Ceyloro menyatukan operasi tersebut melalui satu pola interaksi yang
kontekstual, tetapi tidak boleh menampilkan petal yang belum didukung atau
menyamakan fitur antar-platform tanpa verifikasi.

## 3. Tujuan produk

- Menyediakan satu radial interface untuk conversion, tools, dan file actions.
- Menampilkan hanya operasi yang kompatibel dengan input dan engine aktif.
- Menjaga pengalaman konsep tetap konsisten di macOS, Windows, dan Linux.
- Mempertahankan perilaku native setiap platform.
- Memproses file secara lokal dan offline.
- Memberikan status job, progress, cancellation, error, dan output yang dapat
  dipahami.
- Menjadi fondasi yang jelas untuk model Free dan Premium di kemudian hari.

## 4. Bukan tujuan

- Menggantikan editor foto, audio, atau video profesional.
- Menjamin fidelity sempurna untuk semua format kompleks.
- Mengimplementasikan semua tools pada screenshot sekaligus.
- Memaksakan modifier key dan UI yang sama di semua sistem operasi.
- Menambahkan cloud processing, akun pengguna, atau telemetry sebagai default.

## 5. Model produk

### 5.1 Convert formats

Petal berisi format output, misalnya JPG, PDF, MP4, DOCX, ODS, atau TAR.

### 5.2 File tools

Petal berisi operasi pengolahan, misalnya Compress, Crop, Metadata, Split,
Organize, dan Extract. Tool yang memerlukan parameter harus membuka dialog
konfigurasi sebelum job dimulai.

### 5.3 File actions

Petal berisi tindakan terhadap file atau lokasinya, misalnya Copy, Move, Copy
Path, Terminal, AirDrop, dan Float. File action tidak boleh dianggap sebagai
konversi format.

## 6. Status klasifikasi requirement

Setiap item dalam roadmap harus memiliki salah satu status berikut:

| Status | Arti |
|---|---|
| Existing | Tercatat di baseline dan sudah diverifikasi melalui test |
| Partial | Sebagian alur sudah ada, tetapi cakupan atau QA belum lengkap |
| Verify | Ada di baseline, tetapi belum terbukti pada runtime target |
| Proposed | Target baru dari arah produk atau referensi desain |
| Placeholder | Disebutkan, tetapi belum boleh tampil sebagai fitur aktif |
| Deferred | Sengaja ditunda dari release saat ini |

Screenshot hanya menjadi referensi cakupan dan visual. Status implementasi harus
ditentukan dari source, test, build, dan pengujian runtime.

## 7. Roadmap prioritas

### P0 — Stabilitas dan keselamatan

Scope:

- bug dan audit findings;
- wheel tidak muncul tanpa drag yang valid;
- overlay dan hit-testing;
- drop di luar wheel sebagai pembatalan;
- output anti-timpa;
- batch failure isolation;
- cancellation dan temp cleanup;
- error yang jelas;
- capability filtering;
- build dan release pipeline.

Gate:

- sumber tidak pernah diubah atau dihapus;
- output parsial dibersihkan;
- target yang tidak tersedia tidak muncul;
- job dapat dibatalkan tanpa proses yang menggantung;
- automated test dan smoke test lulus.

### P1 — Core workflow

Scope:

- conversion matrix yang akurat;
- output folder dan kualitas;
- progress per job;
- notifikasi;
- Settings;
- file actions dasar;
- dokumentasi supported formats;
- paket mandiri untuk platform yang didukung.

Gate:

- operasi utama dapat digunakan tanpa konfigurasi manual yang tidak
  didokumentasikan;
- setiap format memiliki batasan yang tertulis;
- output dapat ditemukan pengguna setelah selesai.

### P2 — Workflow produktivitas

Scope:

- queue atau batch lanjutan;
- preset kualitas;
- workflow tersimpan;
- ekstraksi arsip sebagai tool khusus;
- PDF split dan organize;
- image crop dan add background;
- pengelolaan multi-page yang konsisten.

Gate:

- setiap workflow memiliki state konfigurasi, processing, success, error, dan
  cancelled;
- operasi destruktif terhadap output selalu memiliki aturan yang jelas.

### P3 — Advanced tools dan platform parity

Scope:

- audio trim, normalize, channels, visualize, bleep, metadata;
- video trim, crop, speed, mute, split, snapshot, redact, metadata;
- image redact, annotate, edit, metadata;
- PDF metadata dan advanced organize;
- Float;
- parity Windows dan macOS;
- Linux shell tahap awal.

Gate:

- setiap tool memiliki input, output, parameter, fidelity, dan failure mode
  yang terdokumentasi;
- fitur tidak ditampilkan jika backend atau platform tidak mendukungnya.

### P4 — Monetisasi dan pemolesan

Scope:

- pembagian Free/Premium;
- entitlement dan aktivasi;
- custom radial wheel;
- favorit dan shortcut khusus;
- onboarding;
- saved workflows;
- analytics minimal yang menjaga privasi bila kelak disetujui.

Gate:

- Free tetap berguna;
- Premium menjual efisiensi tambahan, bukan mengurangi kualitas fitur dasar;
- lisensi menjelaskan aktivasi, transfer perangkat, update, dan major upgrade.

## 8. Kontrak interaksi global

Setiap platform wajib menyediakan konsep berikut, dengan implementasi native yang
boleh berbeda:

- wheel muncul di dekat pointer atau konteks aktif;
- petal aktif terlihat jelas;
- pusat wheel menampilkan target aktif;
- pilihan menyesuaikan jumlah operasi;
- operasi yang butuh parameter membuka konfigurasi;
- Escape atau dismissal membatalkan dengan aman;
- loading tidak menyamarkan capability yang belum diketahui;
- wheel tidak terpotong monitor atau tertutup panel sistem;
- keyboard navigation tersedia jika platform memungkinkan.

Modifier key tidak dikunci oleh screenshot. Pemetaan final harus ditentukan per
platform setelah conflict test terhadap shortcut sistem dan aplikasi sumber.

## 9. Capability registry

Semua target yang tampil di wheel harus berasal dari registry yang minimal
memiliki:

- kategori operasi;
- format input;
- format output atau tool;
- platform;
- engine dan versi;
- dukungan single-file atau batch;
- opsi yang tersedia;
- dukungan progress dan cancellation;
- batasan fidelity;
- status probing;
- kode dan pesan error.

Registry menjadi sumber bagi wheel, supported-formats catalog, README, dan
diagnostics. Daftar ekstensi hard-coded tidak boleh menjadi satu-satunya sumber
kebenaran.

## 10. Kontrak job lintas-platform

Setiap job harus memiliki:

- `jobId`;
- input paths;
- `operationId`;
- output target;
- validated options;
- status `queued`, `probing`, `running`, `cancelling`, `succeeded`, `failed`,
  atau `cancelled`;
- progress bila tersedia;
- output paths;
- error code dan user-facing message;
- timestamps.

Kegagalan satu item pada batch tidak boleh menghapus hasil item lain atau
menyebabkan status keseluruhan menjadi tidak informatif.

## 11. File safety dan privacy

- File sumber tidak diubah, dihapus, atau ditimpa secara diam-diam.
- Proses eksternal menerima argumen terpisah, bukan shell string mentah.
- Temp directory unik untuk setiap job atau batch.
- Cleanup berjalan pada success, failure, cancellation, dan shutdown yang aman.
- Log tidak menyimpan isi file atau data sensitif yang tidak diperlukan.
- Tidak ada upload file ke cloud sebagai default.
- Archive extraction melindungi dari traversal, symlink berbahaya, dan output
  di luar folder tujuan.
- Nama output konflik selalu menghasilkan nama baru atau meminta keputusan.

## 12. Rencana implementasi berurutan

1. **M0 — Baseline reconciliation:** cocokkan Master PRD, codebase, audit,
   release, dan screenshot.
2. **M1 — Product contract:** bekukan kategori wheel, status, capability,
   job, output, dan error contract.
3. **M2 — P0 hardening:** tutup reliability dan file-safety gap.
4. **M3 — P1 workflow:** stabilkan conversion, settings, progress, actions,
   dan dokumentasi format.
5. **M4 — P2 productivity:** tambahkan preset, archive extract, dan tools
   produktivitas prioritas.
6. **M5 — P3 advanced:** kerjakan tools lanjutan berdasarkan kategori dan
   platform.
7. **M6 — P4 commercial:** finalisasi Free/Premium dan workflow customization.
8. **M7 — Release governance:** QA, packaging, signing, updater, dan support.

## 13. Definition of done master roadmap

Master PRD dianggap siap menjadi acuan implementasi ketika:

- status setiap requirement sudah dicocokkan dengan source dan test;
- P0–P4 telah disetujui urutannya;
- modifier key per platform sudah diputuskan atau diberi status Verify;
- format dan engine memiliki matriks capability;
- Free/Premium belum mengunci fitur yang belum stabil;
- setiap item memiliki acceptance criteria;
- tidak ada screenshot yang diperlakukan sebagai bukti implementasi;
- setiap release dapat dilacak ke requirement dan test yang relevan.

## 14. Status dokumen

Dokumen ini adalah rencana produk. Tidak ada implementasi, perubahan source,
perubahan UI, atau perubahan release yang diwajibkan oleh dokumen ini sebelum
scope fase terkait disetujui secara eksplisit.

