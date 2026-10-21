#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/Pomelo.app"

DEV_DIR="${DEVELOPER_DIR:-}"
if [ -z "$DEV_DIR" ]; then
    for candidate in \
        "/Applications/Xcode.app/Contents/Developer" \
        "/Users/$(id -un)/Downloads/Xcode.app/Contents/Developer"; do
        if [ -x "$candidate/usr/bin/xcodebuild" ]; then
            DEV_DIR="$candidate"
            break
        fi
    done
fi

if [ -z "$DEV_DIR" ]; then
    DEV_DIR=$(xcode-select -p 2>/dev/null || true)
fi

if [ -z "$DEV_DIR" ] || [ ! -x "$DEV_DIR/usr/bin/xcodebuild" ]; then
    echo "Xcode penuh tidak ditemukan. Set DEVELOPER_DIR ke Contents/Developer." >&2
    exit 1
fi

X86_SCRATCH="$ROOT/.build/x86_64-release"
ARM_SCRATCH="$ROOT/.build/arm64-release"
DEVELOPER_DIR="$DEV_DIR" swift build --package-path "$ROOT" -c release --arch x86_64 --scratch-path "$X86_SCRATCH"
DEVELOPER_DIR="$DEV_DIR" swift build --package-path "$ROOT" -c release --arch arm64 --scratch-path "$ARM_SCRATCH"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
    "$X86_SCRATCH/release/Pomelo" \
    "$ARM_SCRATCH/release/Pomelo" \
    -output "$APP/Contents/MacOS/Pomelo"
cp "$ROOT/Sources/Pomelo/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Sources/Pomelo/Resources/Pomelo.icns" ]; then
    cp "$ROOT/Sources/Pomelo/Resources/Pomelo.icns" "$APP/Contents/Resources/Pomelo.icns"
fi
if [ -f "$ROOT/Sources/Pomelo/Resources/PomeloMenuTemplate.png" ]; then
    cp "$ROOT/Sources/Pomelo/Resources/PomeloMenuTemplate.png" "$APP/Contents/Resources/PomeloMenuTemplate.png"
fi
chmod +x "$APP/Contents/MacOS/Pomelo"
codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Pomelo"))"
