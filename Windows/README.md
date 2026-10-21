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

Letakkan `ffmpeg.exe` build LGPL di samping `Ceyloro.exe`, atau pilih file itu
melalui menu **Pengaturan**. Binary FFmpeg tidak disertakan dalam source tree.

Alur penggunaan saat ini: jalankan Ceyloro, tekan `Ctrl+Alt+Space`, lalu tarik
file dari Explorer ke roda dan lepaskan pada target yang diinginkan. `Esc`
membatalkan overlay.
