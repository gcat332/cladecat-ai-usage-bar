#!/bin/bash
# Setup script for Claude Usage Widget

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🤖 Claude Usage Widget — Setup"
echo "================================"

# Check Python 3
if ! command -v python3 &>/dev/null; then
    echo "❌ Python 3 not found. Install via: brew install python"
    exit 1
fi

echo "✅ Python 3 found: $(python3 --version)"

# Install dependencies
echo ""
echo "📦 Installing dependencies..."
pip3 install rumps requests --break-system-packages 2>/dev/null || \
pip3 install rumps requests

echo ""
echo "✅ Dependencies installed!"
echo ""
echo "🚀 Starting Claude Usage Widget..."
echo "   (Look for 🤖 in your menu bar)"
echo ""
echo "   To set your session key:"
echo "   1. Open claude.ai in Chrome/Safari"
echo "   2. Open DevTools (Cmd+Option+I)"
echo "   3. Application tab → Cookies → https://claude.ai"
echo "   4. Copy the value of 'sessionKey'"
echo "   5. Click 🤖 in menu bar → Settings"
echo ""

python3 "$ROOT_DIR/claude_usage_widget.py"
