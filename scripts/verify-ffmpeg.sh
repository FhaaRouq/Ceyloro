#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FFMPEG_PATH="${1:-$ROOT/Sources/Ceyloro/Resources/ffmpeg}"

if [ ! -x "$FFMPEG_PATH" ]; then
    echo "FFmpeg executable tidak ditemukan: $FFMPEG_PATH" >&2
    exit 1
fi

ARCHS=$(lipo -archs "$FFMPEG_PATH")
case " $ARCHS " in
    *" x86_64 "*" arm64 "*"|*" arm64 "*" x86_64 "*") ;;
    *)
        echo "FFmpeg harus universal x86_64 + arm64; arsitektur saat ini: $ARCHS" >&2
        exit 1
        ;;
esac

VERSION=$($FFMPEG_PATH -hide_banner -version | sed -n '1p')
case "$VERSION" in
    *ffmpeg*) echo "$VERSION" ;;
    *)
        echo "File bukan binary FFmpeg yang valid." >&2
        exit 1
        ;;
esac

echo "FFmpeg universal valid: $ARCHS"
