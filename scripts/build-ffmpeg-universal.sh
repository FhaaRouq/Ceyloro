#!/bin/sh
set -eu

# Build a self-contained LGPL-only FFmpeg executable for Ceyloro.
# The resulting binary is intentionally ignored by Git; releases must publish
# the corresponding source/configuration/checksum alongside the app artifact.

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION="${FFMPEG_VERSION:-7.1.1}"
BUILD_ROOT="${CEYLORO_FFMPEG_BUILD_ROOT:-${TMPDIR:-/tmp}/ceyloro-ffmpeg-${VERSION}}"
SOURCE_ARCHIVE="$BUILD_ROOT/ffmpeg-${VERSION}.tar.xz"
SOURCE_URL="https://ffmpeg.org/releases/ffmpeg-${VERSION}.tar.xz"
OUTPUT="$ROOT/Sources/Ceyloro/Resources/ffmpeg"

DEVELOPER_DIR="${DEVELOPER_DIR:-}"
if [ -z "$DEVELOPER_DIR" ]; then
    for candidate in \
        "/Applications/Xcode.app/Contents/Developer" \
        "/Users/$(id -un)/Downloads/Xcode.app/Contents/Developer"; do
        if [ -x "$candidate/usr/bin/xcodebuild" ]; then
            DEVELOPER_DIR="$candidate"
            break
        fi
    done
fi

if [ -z "$DEVELOPER_DIR" ] || [ ! -x "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang" ]; then
    echo "Xcode penuh tidak ditemukan. Set DEVELOPER_DIR ke Contents/Developer." >&2
    exit 1
fi

TOOLCHAIN="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [ ! -d "$SDKROOT" ]; then
    echo "macOS SDK tidak ditemukan: $SDKROOT" >&2
    exit 1
fi

mkdir -p "$BUILD_ROOT"
export CLANG_MODULE_CACHE_PATH="${CEYLORO_CLANG_MODULE_CACHE:-$BUILD_ROOT/module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
if [ ! -f "$SOURCE_ARCHIVE" ]; then
    curl --fail --location --retry 3 --output "$SOURCE_ARCHIVE" "$SOURCE_URL"
fi

SOURCE_DIR="$BUILD_ROOT/ffmpeg-${VERSION}"
if [ ! -d "$SOURCE_DIR" ]; then
    tar -xJf "$SOURCE_ARCHIVE" -C "$BUILD_ROOT"
fi

JOBS="${CEYLORO_FFMPEG_JOBS:-}"
if [ -z "$JOBS" ]; then
    JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 2)
fi

COMMON_FLAGS="--prefix=%PREFIX% --cc=$TOOLCHAIN/clang --cxx=$TOOLCHAIN/clang++ --host-cc=$TOOLCHAIN/clang --ar=$TOOLCHAIN/ar --ranlib=$TOOLCHAIN/ranlib --strip=$TOOLCHAIN/strip --pkg-config=false --disable-debug --disable-doc --disable-ffplay --disable-ffprobe --disable-gpl --disable-nonfree --disable-x86asm --disable-shared --enable-static --enable-videotoolbox --enable-audiotoolbox --extra-version=ceyloro"

for ARCH in x86_64 arm64; do
    PREFIX="$BUILD_ROOT/install-$ARCH"
    BUILD_DIR="$BUILD_ROOT/build-$ARCH"
    if [ -x "$PREFIX/bin/ffmpeg" ]; then
        echo "Menggunakan slice $ARCH yang sudah selesai: $PREFIX/bin/ffmpeg"
        continue
    fi
    rm -rf "$BUILD_DIR" "$PREFIX"
    mkdir -p "$BUILD_DIR" "$PREFIX"
    CFLAGS="-arch $ARCH -mmacosx-version-min=13.0 -isysroot $SDKROOT"
    LDFLAGS="-arch $ARCH -mmacosx-version-min=13.0 -isysroot $SDKROOT -framework VideoToolbox -framework AudioToolbox -framework CoreMedia -framework CoreVideo"
    HOST_CFLAGS="-arch x86_64 -mmacosx-version-min=13.0 -isysroot $SDKROOT"
    HOST_LDFLAGS="-arch x86_64 -mmacosx-version-min=13.0 -isysroot $SDKROOT"
    TARGET_FLAGS="--target-os=darwin --arch=$ARCH"
    if [ "$ARCH" = "arm64" ]; then
        TARGET_FLAGS="$TARGET_FLAGS --enable-cross-compile"
    fi
    (
        cd "$BUILD_DIR"
        # shellcheck disable=SC2086
        "$SOURCE_DIR/configure" $TARGET_FLAGS $(printf '%s' "$COMMON_FLAGS" | sed "s|%PREFIX%|$PREFIX|g") \
            --extra-cflags="$CFLAGS" \
            --extra-ldflags="$LDFLAGS" \
            --host-cflags="$HOST_CFLAGS" \
            --host-ldflags="$HOST_LDFLAGS"
        make -j"$JOBS"
        make install
    )
done

mkdir -p "$(dirname -- "$OUTPUT")"
lipo -create \
    "$BUILD_ROOT/install-x86_64/bin/ffmpeg" \
    "$BUILD_ROOT/install-arm64/bin/ffmpeg" \
    -output "$OUTPUT"
chmod +x "$OUTPUT"

echo "FFmpeg source: $SOURCE_URL"
echo "FFmpeg output: $OUTPUT"
"$ROOT/scripts/verify-ffmpeg.sh" "$OUTPUT"
echo "SHA-256: $(shasum -a 256 "$OUTPUT" | awk '{print $1}')"
echo "Build config: LGPL-only, --disable-gpl --disable-nonfree, macOS 13+, x86_64 + arm64"
