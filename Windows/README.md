# Ceyloro Windows shell

Shell Windows pertama Ceyloro memakai WinForms bawaan .NET 8, sehingga tidak
memerlukan paket NuGet tambahan. Shell ini menyediakan:

- ikon system tray;
- hotkey `Ctrl+Alt+Space` untuk membuka roda;
- drag-and-drop file dari Explorer ke overlay;
- target format yang disaring dari jenis file yang dipilih;
- konversi batch berbasis FFmpeg, dengan progres, pembatalan, output unik, dan
  laporan kegagalan per file;
- Settings untuk folder output dan lokasi `ffmpeg.exe`.

## Build di Windows

Pasang Visual Studio 2022 dengan workload **.NET desktop development**, lalu:

```powershell
dotnet build .\Windows\Ceyloro.Windows\Ceyloro.Windows.csproj -c Release
```

Paket release resmi sudah membawa `ffmpeg.exe` build LGPL di samping `Ceyloro.exe`.
Build dari source tree tidak membawa binary itu; letakkan `ffmpeg.exe` build LGPL
di samping executable atau pilih file tersebut melalui menu **Pengaturan**.

Alur penggunaan saat ini: jalankan Ceyloro, tekan `Ctrl+Alt+Space`, lalu tarik
file dari Explorer ke roda dan lepaskan pada target yang diinginkan. `Esc`
membatalkan overlay.
