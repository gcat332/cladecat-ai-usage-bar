#!/bin/bash
# Double-click เพื่อเปิด Claude Cat widget
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

python3 -c "import rumps" 2>/dev/null || {
    echo "Installing rumps..."
    pip3 install rumps --break-system-packages 2>/dev/null || pip3 install rumps
}

python3 claude_usage_widget.py
