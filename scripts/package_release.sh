#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

VERSION="1.0.0"
APP="ClaudeCat.app"
DIST="dist"
ZIP="$DIST/ClaudeCat-$VERSION.zip"

if ! command -v swiftc &>/dev/null; then
    echo "❌ ไม่มี swiftc — ติดตั้งก่อน: xcode-select --install"
    exit 1
fi

echo "🔨 Building $APP ..."
rm -rf "$APP" "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"
cp ClaudeCatApp/Info.plist "$APP/Contents/Info.plist"
[ -f assets/bcat.icns ] && cp assets/bcat.icns "$APP/Contents/Resources/"
[ -f assets/cat_icon.png ] && cp assets/cat_icon.png "$APP/Contents/Resources/"
[ -f assets/cute2.png ] && cp assets/cute2.png "$APP/Contents/Resources/"
[ -f assets/cute3.png ] && cp assets/cute3.png "$APP/Contents/Resources/"
[ -f assets/claude_logo.png ] && cp assets/claude_logo.png "$APP/Contents/Resources/"
[ -f assets/codex_logo.png ] && cp assets/codex_logo.png "$APP/Contents/Resources/"

swiftc -O ClaudeCatApp/*.swift -o "$APP/Contents/MacOS/ClaudeCat"
codesign --force -s - "$APP" 2>/dev/null || true

ditto -c -k --keepParent "$APP" "$ZIP"
echo "✅ Release package: $PWD/$ZIP"
