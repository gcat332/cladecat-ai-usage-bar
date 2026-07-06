#!/bin/bash
# ติดตั้ง Claude Cat ให้เปิดอัตโนมัติทุกครั้งที่ Login

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON="$(which python3)"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/com.claude.usagewidget.plist"
LOG="$HOME/.claude_widget.log"

echo "🐱 Claude Cat — Auto-start Setup"
echo "==========================================="
echo ""

# ── ติดตั้ง dependencies ──────────────────────────────────────────────────────
echo "📦 ติดตั้ง dependencies..."
"$PYTHON" -m pip install rumps --break-system-packages -q 2>/dev/null \
  || "$PYTHON" -m pip install rumps -q
echo "✅ Dependencies OK"
echo ""

# ── สร้าง LaunchAgents folder ─────────────────────────────────────────────────
mkdir -p "$PLIST_DIR"

# ── หยุด widget เก่า (ถ้ามี) ─────────────────────────────────────────────────
launchctl unload "$PLIST" 2>/dev/null || true

# ── สร้าง plist ───────────────────────────────────────────────────────────────
cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.usagewidget</string>

    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON</string>
        <string>$ROOT_DIR/claude_usage_widget.py</string>
    </array>

    <!-- เปิดทันทีเมื่อ load -->
    <key>RunAtLoad</key>
    <true/>

    <!-- restart อัตโนมัติถ้า crash -->
    <key>KeepAlive</key>
    <true/>

    <!-- เก็บ log -->
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>

    <!-- รอให้ UI พร้อมก่อน (ป้องกันเปิดก่อน menu bar โหลด) -->
    <key>ThrottleInterval</key>
    <integer>5</integer>
</dict>
</plist>
EOF

echo "📄 สร้าง plist ที่: $PLIST"

# ── โหลด LaunchAgent ─────────────────────────────────────────────────────────
launchctl load "$PLIST"
echo ""
echo "✅ เปิดใช้งาน Auto-start สำเร็จ!"
echo "   🐱 Claude Cat จะเปิดอัตโนมัติทุกครั้งที่ Login"
echo ""
echo "── คำสั่งที่มีประโยชน์ ──────────────────────────────"
echo "  หยุด widget:         launchctl unload '$PLIST'"
echo "  เปิด widget ใหม่:    launchctl load   '$PLIST'"
echo "  ถอนการติดตั้ง:       rm '$PLIST'"
echo "  ดู log:              tail -f $LOG"
echo "─────────────────────────────────────────────────────"
