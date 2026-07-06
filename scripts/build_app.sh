#!/bin/bash
# Build ClaudeCat.app จาก source แล้ว (option) เพิ่มเข้า Login Items
# ต้องมี Xcode Command Line Tools: xcode-select --install
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v swiftc &>/dev/null; then
    echo "❌ ไม่มี swiftc — ติดตั้งก่อน: xcode-select --install"
    exit 1
fi

APP="ClaudeCat.app"
echo "🔨 Building $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ClaudeCatApp/Info.plist "$APP/Contents/Info.plist"
[ -f assets/bcat.icns ] && cp assets/bcat.icns "$APP/Contents/Resources/"
[ -f assets/cat_icon.png ] && cp assets/cat_icon.png "$APP/Contents/Resources/"
[ -f assets/cute2.png ] && cp assets/cute2.png "$APP/Contents/Resources/"
[ -f assets/cute3.png ] && cp assets/cute3.png "$APP/Contents/Resources/"
[ -f assets/claude_logo.png ] && cp assets/claude_logo.png "$APP/Contents/Resources/"
[ -f assets/codex_logo.png ] && cp assets/codex_logo.png "$APP/Contents/Resources/"

swiftc -O ClaudeCatApp/main.swift -o "$APP/Contents/MacOS/ClaudeCat"
codesign --force -s - "$APP" 2>/dev/null || true
echo "✅ Build สำเร็จ: $PWD/$APP"

echo ""
read -p "เพิ่มเข้า Login Items (เปิดอัตโนมัติตอน login) เลย? [y/N] " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$PWD/$APP\", hidden:false}" >/dev/null
    echo "✅ เพิ่มเข้า Login Items แล้ว"
fi

echo ""
echo "🚀 เปิดเลย: open \"$PWD/$APP\""
read -p "เปิดตอนนี้? [Y/n] " yn
[[ ! "$yn" =~ ^[Nn]$ ]] && open "$APP"
