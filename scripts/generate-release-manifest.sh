#!/bin/sh
# C5: Generate release-manifest.json untuk distribusi Ceyloro.
# Digunakan oleh job release di release-desktop.yml setelah semua artefak diunduh.
#
# Usage: RELEASE_TAG="v0.1.1" ./scripts/generate-release-manifest.sh <dist-dir>
# Output: JSON ke stdout

set -eu

DIST_DIR="${1:-dist}"
RELEASE_TAG="${RELEASE_TAG:-unknown}"
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

sha256_for() {
    if [ -f "$1.sha256" ]; then
        awk '{print $1}' "$1.sha256"
    elif [ -f "$1" ]; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "N/A"
    fi
}

size_for() {
    if [ -f "$1" ]; then
        wc -c < "$1" | tr -d ' '
    else
        echo "0"
    fi
}

MACOS_ZIP="$DIST_DIR/Ceyloro-macOS-universal.zip"
WIN_X64_ZIP="$DIST_DIR/Ceyloro-Windows-x64.zip"
WIN_ARM64_ZIP="$DIST_DIR/Ceyloro-Windows-arm64.zip"

cat <<JSON
{
  "version": "$RELEASE_TAG",
  "generatedAt": "$GENERATED_AT",
  "platforms": {
    "macos": {
      "filename": "Ceyloro-macOS-universal.zip",
      "sha256": "$(sha256_for "$MACOS_ZIP")",
      "size": $(size_for "$MACOS_ZIP"),
      "architecture": "universal (x86_64 + arm64)",
      "minimumOS": "13.0"
    },
    "windows-x64": {
      "filename": "Ceyloro-Windows-x64.zip",
      "sha256": "$(sha256_for "$WIN_X64_ZIP")",
      "size": $(size_for "$WIN_X64_ZIP"),
      "architecture": "x64",
      "minimumOS": "Windows 10 (build 19041)"
    },
    "windows-arm64": {
      "filename": "Ceyloro-Windows-arm64.zip",
      "sha256": "$(sha256_for "$WIN_ARM64_ZIP")",
      "size": $(size_for "$WIN_ARM64_ZIP"),
      "architecture": "arm64",
      "minimumOS": "Windows 10 (build 19041)"
    }
  }
}
JSON
