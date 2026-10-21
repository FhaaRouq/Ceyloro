#!/bin/sh
set -eu

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

XCTEST_FRAMEWORK="$DEV_DIR/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework"

if [ -d "$XCTEST_FRAMEWORK" ]; then
    DEVELOPER_DIR="$DEV_DIR" swift test
else
    echo "Skipping XCTest: full Xcode/XCTest.framework is not available."
    echo "Install Xcode or set DEVELOPER_DIR to its Contents/Developer directory."
fi

DEVELOPER_DIR="$DEV_DIR" swift build -c release
