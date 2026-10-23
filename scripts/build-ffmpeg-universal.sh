#!/bin/sh
set -eu

# Build a self-contained LGPL-only FFmpeg executable for Ceyloro.
# The resulting binary is intentionally ignored by Git; releases must publish
# the corresponding source/configuration/checksum alongside the app artifact.

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION="${FFMPEG_VERSION:-7.1.1}"
SHINE_VERSION="${SHINE_VERSION:-3.1.1}"
BUILD_ROOT="${CEYLORO_FFMPEG_BUILD_ROOT:-${TMPDIR:-/tmp}/ceyloro-ffmpeg-${VERSION}}"
SOURCE_ARCHIVE="$BUILD_ROOT/ffmpeg-${VERSION}.tar.xz"
SOURCE_URL="https://ffmpeg.org/releases/ffmpeg-${VERSION}.tar.xz"
SHINE_ARCHIVE="$BUILD_ROOT/shine-${SHINE_VERSION}.tar.gz"
SHINE_SOURCE_URL="https://github.com/savonet/shine/archive/refs/tags/${SHINE_VERSION}.tar.gz"
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

# C3: Verifikasi checksum SHA-256 sumber FFmpeg setelah unduhan, sebelum ekstraksi.
# Nilai ini harus diperbarui setiap kali VERSION berubah.
# Cara memperbarui: unduh arsip baru, jalankan `shasum -a 256 <file>`, lalu
# salin nilai hash ke variabel yang sesuai di bawah ini.
# SHA-256 untuk ffmpeg-7.1.1.tar.xz (sumber: homebrew-core)
FFMPEG_SHA256_EXPECTED="06ad4d7e0449e6e67c8d2b2ba042144f2fb054e90d8591b6786bcb3248d95b00"
# Override via environment untuk CI atau build otomatis:
FFMPEG_SHA256="${FFMPEG_SHA256_OVERRIDE:-$FFMPEG_SHA256_EXPECTED}"

if [ -n "$FFMPEG_SHA256" ] && [ "$FFMPEG_SHA256" != "skip" ]; then
    ACTUAL_SHA256=$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{print $1}')
    if [ "$ACTUAL_SHA256" != "$FFMPEG_SHA256" ]; then
        echo "Error: Checksum FFmpeg tidak cocok." >&2
        echo "  Diharapkan: $FFMPEG_SHA256" >&2
        echo "  Diterima:   $ACTUAL_SHA256" >&2
        echo "Jika kamu baru mengubah VERSION, perbarui FFMPEG_SHA256_EXPECTED di script ini." >&2
        rm -f "$SOURCE_ARCHIVE"
        exit 1
    fi
    echo "FFmpeg source checksum terverifikasi: $ACTUAL_SHA256"
fi

SOURCE_DIR="$BUILD_ROOT/ffmpeg-${VERSION}"
if [ ! -d "$SOURCE_DIR" ]; then
    tar -xJf "$SOURCE_ARCHIVE" -C "$BUILD_ROOT"
fi

SHINE_SOURCE_DIR="$BUILD_ROOT/shine-${SHINE_VERSION}"
if [ ! -f "$SHINE_ARCHIVE" ]; then
    curl --fail --location --retry 3 --output "$SHINE_ARCHIVE" "$SHINE_SOURCE_URL"
fi
if [ ! -d "$SHINE_SOURCE_DIR" ]; then
    tar -xzf "$SHINE_ARCHIVE" -C "$BUILD_ROOT"
fi

JOBS="${CEYLORO_FFMPEG_JOBS:-}"
if [ -z "$JOBS" ]; then
    JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 2)
fi

COMMON_FLAGS="--prefix=%PREFIX% --cc=$TOOLCHAIN/clang --cxx=$TOOLCHAIN/clang++ --host-cc=$TOOLCHAIN/clang --ar=$TOOLCHAIN/ar --ranlib=$TOOLCHAIN/ranlib --strip=$TOOLCHAIN/strip --disable-debug --disable-doc --disable-ffplay --disable-ffprobe --disable-gpl --disable-nonfree --disable-x86asm --disable-shared --enable-static --enable-libshine --enable-videotoolbox --enable-audiotoolbox --extra-version=ceyloro"

build_shine() {
    ARCH="$1"
    SHINE_PREFIX_LOCAL="$BUILD_ROOT/shine-install-$ARCH"
    SHINE_BUILD_DIR_LOCAL="$BUILD_ROOT/shine-build-$ARCH"
    if [ -f "$SHINE_PREFIX_LOCAL/lib/libshine.a" ]; then
        return
    fi
    rm -rf "$SHINE_BUILD_DIR_LOCAL" "$SHINE_PREFIX_LOCAL"
    mkdir -p "$SHINE_BUILD_DIR_LOCAL/obj" "$SHINE_PREFIX_LOCAL/include/shine" "$SHINE_PREFIX_LOCAL/lib/pkgconfig"
    cp "$SHINE_SOURCE_DIR/src/lib/layer3.h" "$SHINE_PREFIX_LOCAL/include/shine/layer3.h"
    SHINE_CFLAGS="-arch $ARCH -mmacosx-version-min=13.0 -isysroot $SDKROOT -O2 -funroll-loops -fno-exceptions -Wall -fsigned-char -I$SHINE_SOURCE_DIR/src/lib"
    for source in "$SHINE_SOURCE_DIR"/src/lib/*.c; do
        object="$SHINE_BUILD_DIR_LOCAL/obj/$(basename "${source%.c}").o"
        # shellcheck disable=SC2086
        "$TOOLCHAIN/clang" $SHINE_CFLAGS -c "$source" -o "$object"
    done
    "$TOOLCHAIN/ar" rcs "$SHINE_PREFIX_LOCAL/lib/libshine.a" "$SHINE_BUILD_DIR_LOCAL"/obj/*.o
    "$TOOLCHAIN/ranlib" "$SHINE_PREFIX_LOCAL/lib/libshine.a"
    cat > "$SHINE_PREFIX_LOCAL/lib/pkgconfig/shine.pc" <<EOF
prefix=$SHINE_PREFIX_LOCAL
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: shine
Description: Fixed-point MP3 encoder
Version: $SHINE_VERSION
Libs: -L\${libdir} -lshine -lm
Cflags: -I\${includedir}
EOF
}

for ARCH in x86_64 arm64; do
    PREFIX="$BUILD_ROOT/install-$ARCH"
    BUILD_DIR="$BUILD_ROOT/build-$ARCH"
    if [ -x "$PREFIX/bin/ffmpeg" ] && [ -f "$PREFIX/.ceyloro-shine-enabled" ]; then
        echo "Menggunakan slice $ARCH yang sudah selesai: $PREFIX/bin/ffmpeg"
        continue
    fi
    rm -rf "$BUILD_DIR" "$PREFIX"
    mkdir -p "$BUILD_DIR" "$PREFIX"
    build_shine "$ARCH"
    SHINE_PREFIX="$BUILD_ROOT/shine-install-$ARCH"
    PKG_CONFIG_SHINE="$BUILD_ROOT/pkg-config-shine-$ARCH"
    cat > "$PKG_CONFIG_SHINE" <<EOF
#!/bin/sh
case "\$*" in
    --version*) printf '%s\\n' '1.8.1' ;;
    *--exists*) exit 0 ;;
    *--cflags*) printf '%s\\n' '-I$SHINE_PREFIX/include' ;;
    *--libs*) printf '%s\\n' '-L$SHINE_PREFIX/lib -lshine -lm' ;;
    *--variable=includedir*) printf '%s\\n' '$SHINE_PREFIX/include' ;;
    *--cflags-only-I*) printf '%s\\n' '-I$SHINE_PREFIX/include' ;;
    *--modversion*) printf '%s\\n' '$SHINE_VERSION' ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$PKG_CONFIG_SHINE"
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
            --pkg-config="$PKG_CONFIG_SHINE" \
            --extra-cflags="$CFLAGS" \
            --extra-ldflags="$LDFLAGS -L$SHINE_PREFIX/lib" \
            --extra-libs="-lshine -lm" \
            --host-cflags="$HOST_CFLAGS" \
            --host-ldflags="$HOST_LDFLAGS"
        make -j"$JOBS"
        make install
    )
    touch "$PREFIX/.ceyloro-shine-enabled"
done

mkdir -p "$(dirname -- "$OUTPUT")"
lipo -create \
    "$BUILD_ROOT/install-x86_64/bin/ffmpeg" \
    "$BUILD_ROOT/install-arm64/bin/ffmpeg" \
    -output "$OUTPUT"
chmod +x "$OUTPUT"

echo "FFmpeg source: $SOURCE_URL"
echo "libshine source: $SHINE_SOURCE_URL"
echo "FFmpeg output: $OUTPUT"
"$ROOT/scripts/verify-ffmpeg.sh" "$OUTPUT"
echo "SHA-256: $(shasum -a 256 "$OUTPUT" | awk '{print $1}')"
echo "Build config: LGPL-only, libshine $SHINE_VERSION, --disable-gpl --disable-nonfree, macOS 13+, x86_64 + arm64"
