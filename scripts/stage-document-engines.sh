#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DESTINATION=${1:-"$ROOT/Sources/Ceyloro/Resources/DocumentEngines"}
SOURCE_ROOT=${CEYLORO_DOCUMENT_ENGINES_PATH:-}
PANDOC_SOURCE=${CEYLORO_PANDOC_PATH:-}

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
