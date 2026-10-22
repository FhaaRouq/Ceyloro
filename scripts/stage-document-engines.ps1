[CmdletBinding()]
param(
    [string]$Destination = "document-engines"
)

$ErrorActionPreference = "Stop"
$root = (Get-Location).Path
$sourceRoot = $env:CEYLORO_DOCUMENT_ENGINES_PATH
$pandocSource = $env:CEYLORO_PANDOC_PATH

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

if ($sourceRoot) {
    if (-not (Test-Path $sourceRoot -PathType Container)) {
        throw "Folder engine dokumen tidak ditemukan: $sourceRoot"
    }
    Copy-Item (Join-Path $sourceRoot '*') $Destination -Recurse -Force
}

$libreOfficeExecutable = Join-Path $Destination 'LibreOffice\program\soffice.exe'
if (-not (Test-Path $libreOfficeExecutable -PathType Leaf)) {
    $candidates = @(
        (Join-Path ${env:ProgramFiles} 'LibreOffice\program\soffice.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'LibreOffice\program\soffice.exe')
    ) | Where-Object { $_ -and (Test-Path $_ -PathType Leaf) }
    if ($candidates.Count -gt 0) {
        $installRoot = Split-Path (Split-Path $candidates[0] -Parent) -Parent
        Copy-Item $installRoot (Join-Path $Destination 'LibreOffice') -Recurse -Force
    }
}

if (-not $pandocSource) {
    $command = Get-Command pandoc.exe -ErrorAction SilentlyContinue
    if ($command) { $pandocSource = $command.Source }
}
if (-not $pandocSource) {
    $command = Get-Command pandoc -ErrorAction SilentlyContinue
    if ($command) { $pandocSource = $command.Source }
}
if ($pandocSource -and (Test-Path $pandocSource -PathType Leaf)) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Destination 'pandoc') | Out-Null
    Copy-Item $pandocSource (Join-Path $Destination 'pandoc\pandoc.exe') -Force
}

if (-not (Test-Path $libreOfficeExecutable -PathType Leaf)) {
    throw "LibreOffice belum ditemukan. Pasang LibreOffice atau set CEYLORO_DOCUMENT_ENGINES_PATH."
}
if (-not (Test-Path (Join-Path $Destination 'pandoc\pandoc.exe') -PathType Leaf)) {
    throw "pandoc belum ditemukan. Pasang pandoc atau set CEYLORO_PANDOC_PATH."
}

Write-Host "Engine dokumen siap dibundel di: $Destination"
& $libreOfficeExecutable --version 2>$null | Select-Object -First 1
& (Join-Path $Destination 'pandoc\pandoc.exe') --version 2>$null | Select-Object -First 1
