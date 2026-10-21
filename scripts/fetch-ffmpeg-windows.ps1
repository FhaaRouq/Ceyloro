param(
    [string]$Destination = "ffmpeg-package",
    [ValidateSet("x64", "arm64")]
    [string]$Architecture = "x64",
    [string]$Release = "autobuild-2026-10-20-13-08",
    [string]$Build = "N-127790-g56dbd4cd37",
    [string]$ExpectedSha256 = ""
)

$ErrorActionPreference = "Stop"

$expectedByArchitecture = @{
    x64 = "ca67d7b3bf3c73a9ffcd670a9216c227829635198355fa6edd46140464c8b58b"
    arm64 = "e7f3c24349197c6d2b9145aeba6f9f8f60f68d221b015658c915f94184723f9d"
}
if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
    $ExpectedSha256 = $expectedByArchitecture[$Architecture]
}
$platform = if ($Architecture -eq "arm64") { "winarm64" } else { "win64" }
$asset = "ffmpeg-$Build-$platform-lgpl.zip"
$baseURL = "https://github.com/BtbN/FFmpeg-Builds/releases/download/$Release"
$archiveURL = "$baseURL/$asset"
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ceyloro-ffmpeg-$Build-$Architecture"
$archivePath = Join-Path $temporaryRoot $asset
$extractPath = Join-Path $temporaryRoot "extracted"

if (Test-Path $temporaryRoot) {
    Remove-Item $temporaryRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

Write-Host "Mengunduh FFmpeg LGPL Windows dari $archiveURL"
Invoke-WebRequest -Uri $archiveURL -OutFile $archivePath

$actualSha256 = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -ne $ExpectedSha256.ToLowerInvariant()) {
    throw "Checksum FFmpeg tidak cocok. Diharapkan $ExpectedSha256, diterima $actualSha256."
}

Expand-Archive -Path $archivePath -DestinationPath $extractPath -Force
$binary = Get-ChildItem -Path $extractPath -Filter "ffmpeg.exe" -File -Recurse | Select-Object -First 1
if ($null -eq $binary) {
    throw "ffmpeg.exe tidak ditemukan di dalam arsip yang diverifikasi."
}
Copy-Item $binary.FullName (Join-Path $Destination "ffmpeg.exe") -Force
$probe = Get-ChildItem -Path $extractPath -Filter "ffprobe.exe" -File -Recurse | Select-Object -First 1
if ($null -eq $probe) {
    throw "ffprobe.exe tidak ditemukan di dalam arsip yang diverifikasi."
}
Copy-Item $probe.FullName (Join-Path $Destination "ffprobe.exe") -Force

$notice = @"
Ceyloro bundles FFmpeg LGPL for Windows $Architecture.

Build: $Build
Architecture: $Architecture
Source: https://github.com/BtbN/FFmpeg-Builds/releases/tag/$Release
Archive: $asset
SHA-256: $actualSha256
License: LGPL. FFmpeg is a separate third-party component and is not part of Ceyloro's MIT-licensed core.
"@
Set-Content -Path (Join-Path $Destination "FFmpeg-LICENSE.txt") -Value $notice -Encoding UTF8

Write-Host "FFmpeg Windows tervalidasi: $actualSha256"
