# Build Secrets Ceyloro

Dokumen ini mendokumentasikan secret apa saja yang diperlukan untuk build
berbagai fitur Ceyloro, termasuk cara mendapatkannya — tanpa menuliskan
nilai aktualnya.

---

## macOS — Code Signing dan Notarization

### `APPLE_SIGNING_IDENTITY`

Identity string Developer ID Application untuk menandatangani app macOS.

Format: `Developer ID Application: Nama Developer (XXXXXXXXXX)`

Cara mendapatkan:
1. Daftar ke [Apple Developer Program](https://developer.apple.com/programs/).
2. Buat sertifikat "Developer ID Application" di Certificates, Identifiers & Profiles.
3. Pasang sertifikat di Keychain Mac.
4. Jalankan `security find-identity -v -p codesigning` untuk mendapatkan string identity.

---

### `APPLE_TEAM_ID`

ID tim Apple Developer (10 karakter alfanumerik).

Cara mendapatkan: Lihat di [developer.apple.com/account](https://developer.apple.com/account)
di bagian "Membership Details".

---

### `APPLE_NOTARIZE_APPLE_ID`

Alamat email Apple ID yang terdaftar sebagai anggota Developer Program.

Cara mendapatkan: Email yang digunakan untuk login ke developer.apple.com.

---

### `APPLE_NOTARIZE_PASSWORD`

App-specific password untuk notarytool (bukan password Apple ID utama).

Cara mendapatkan:
1. Login ke [appleid.apple.com](https://appleid.apple.com).
2. Di bagian "Sign-In and Security", pilih "App-Specific Passwords".
3. Buat password baru dengan label "Ceyloro Notarization".

---

## Windows — Authenticode Signing

### `WINDOWS_SIGNING_CERT_PFX`

Sertifikat code-signing Windows dalam format PFX, di-encode ke base64.

Cara mendapatkan:
1. Beli sertifikat Code Signing EV dari CA terpercaya (DigiCert, Sectigo, dll.)
2. Ekspor sertifikat ke format PFX: `certutil -exportpfx ...`
3. Encode ke base64: `certutil -encode cert.pfx cert.b64`, lalu salin isinya.

### `WINDOWS_SIGNING_CERT_PASSWORD`

Password untuk file PFX di atas.

---

## Catatan

- Semua secret di atas bersifat **opsional** untuk build development dan CI biasa.
  Build fungsional untuk free tier tetap dapat dihasilkan tanpa secret apapun.
- Signing dan notarization hanya diaktifkan saat secret tersedia (kondisional di
  `.github/workflows/release-desktop.yml`).
- Jangan pernah menuliskan nilai aktual secret di repository, log, atau dokumentasi.
- Untuk build release publik, semua secret harus diisi di GitHub Actions Secrets
  pada repository settings.
