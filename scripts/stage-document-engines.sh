#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DESTINATION=${1:-"$ROOT/Sources/Ceyloro/Resources/DocumentEngines"}
SOURCE_ROOT=${CEYLORO_DOCUMENT_ENGINES_PATH:-}
PANDOC_SOURCE=${CEYLORO_PANDOC_PATH:-}

# Guard A3: SOURCE_ROOT dan DESTINATION tidak boleh menunjuk ke path yang sama.
# Jika sama, cp -R akan menyalin folder ke dirinya sendiri dan dapat merusak isi.
if [ -n "$SOURCE_ROOT" ]; then
    RESOLVED_SOURCE=$(CDPATH= cd -- "$SOURCE_ROOT" 2>/dev/null && pwd || echo "$SOURCE_ROOT")
    RESOLVED_DEST=$(mkdir -p "$DESTINATION" && CDPATH= cd -- "$DESTINATION" && pwd)
    if [ "$RESOLVED_SOURCE" = "$RESOLVED_DEST" ]; then
        echo "Error: CEYLORO_DOCUMENT_ENGINES_PATH dan DESTINATION menunjuk ke path yang sama: $RESOLVED_SOURCE" >&2
        echo "Pisahkan source dan destination agar cp -R tidak menyalin folder ke dirinya sendiri." >&2
        exit 1
    fi
fi

if [ -n "$SOURCE_ROOT" ] && [ ! -d "$SOURCE_ROOT" ]; then
    echo "Folder engine dokumen tidak ditemukan: $SOURCE_ROOT" >&2
    exit 1
fi

mkdir -p "$DESTINATION"

if [ -n "$SOURCE_ROOT" ]; then
    cp -R "$SOURCE_ROOT"/. "$DESTINATION"/
fi

if [ ! -x "$DESTINATION/LibreOffice.app/Contents/MacOS/soffice" ]; then
    for candidate in \
        "/Applications/LibreOffice.app" \
        "$HOME/Applications/LibreOffice.app"; do
        if [ -x "$candidate/Contents/MacOS/soffice" ]; then
            mkdir -p "$DESTINATION/LibreOffice.app"
            cp -R "$candidate"/. "$DESTINATION/LibreOffice.app"/
            break
        fi
    done
fi

if [ -z "$PANDOC_SOURCE" ]; then
    PANDOC_SOURCE=$(command -v pandoc 2>/dev/null || true)
fi
if [ -z "$PANDOC_SOURCE" ]; then
    for candidate in \
        "/opt/homebrew/bin/pandoc" \
        "/usr/local/bin/pandoc"; do
        if [ -x "$candidate" ]; then
            PANDOC_SOURCE="$candidate"
            break
        fi
    done
fi
if [ -n "$PANDOC_SOURCE" ] && [ -x "$PANDOC_SOURCE" ]; then
    mkdir -p "$DESTINATION/pandoc"
    cp "$PANDOC_SOURCE" "$DESTINATION/pandoc/pandoc"
    chmod +x "$DESTINATION/pandoc/pandoc"
fi

if [ ! -x "$DESTINATION/LibreOffice.app/Contents/MacOS/soffice" ]; then
    echo "LibreOffice belum ditemukan. Pasang LibreOffice atau set CEYLORO_DOCUMENT_ENGINES_PATH." >&2
    exit 1
fi
if [ ! -x "$DESTINATION/pandoc/pandoc" ]; then
    echo "pandoc belum ditemukan. Pasang pandoc atau set CEYLORO_PANDOC_PATH." >&2
    exit 1
fi

echo "Engine dokumen siap dibundel di: $DESTINATION"
"$DESTINATION/LibreOffice.app/Contents/MacOS/soffice" --version 2>/dev/null | head -n 1 || true
"$DESTINATION/pandoc/pandoc" --version 2>/dev/null | head -n 1 || true
