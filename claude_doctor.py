#!/usr/bin/env python3
"""
Claude Cat Doctor — เช็คทีละขั้นว่า widget พังตรงไหน
รัน:  python3 claude_doctor.py
ไม่ต้องติดตั้งอะไรเพิ่ม (stdlib ล้วน)
"""

import json
import os
import subprocess
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone

KEYCHAIN_SERVICE = "Claude Code-credentials"
CREDS_FILE = os.path.expanduser("~/.claude/.credentials.json")
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"


def step(n, txt):
    print(f"\n[{n}] {txt}")


def ok(txt):
    print(f"    ✅ {txt}")


def bad(txt):
    print(f"    ❌ {txt}")


def main():
    print("Claude Cat Doctor")
    print("=" * 50)

    # 1. Keychain
    step(1, "อ่าน Keychain item 'Claude Code-credentials'")
    oauth = None
    try:
        r = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=30,
        )
        if r.returncode == 0 and r.stdout.strip():
            ok("เจอใน Keychain")
            oauth = json.loads(r.stdout.strip()).get("claudeAiOauth")
        else:
            bad(f"ไม่เจอ (returncode={r.returncode}) stderr: {r.stderr.strip()[:100]}")
            print("    → ถ้ามี popup ขอ permission ให้กด 'Always Allow' แล้วรันใหม่")
    except Exception as e:
        bad(f"{e}")

    # 2. fallback file
    if not oauth:
        step(2, f"ลองอ่าน {CREDS_FILE}")
        if os.path.exists(CREDS_FILE):
            try:
                with open(CREDS_FILE) as f:
                    oauth = json.load(f).get("claudeAiOauth")
                ok("เจอไฟล์ credentials")
            except Exception as e:
                bad(f"อ่านไฟล์ไม่ได้: {e}")
        else:
            bad("ไม่มีไฟล์")
    else:
        step(2, "ข้าม (ได้จาก Keychain แล้ว)")

    if not oauth or not oauth.get("accessToken"):
        print("\n💀 สรุป: ไม่มี OAuth credentials ในเครื่อง")
        print("   แก้: เปิด Terminal รัน `claude` แล้ว login ให้เสร็จ 1 ครั้ง จากนั้นรัน doctor ใหม่")
        sys.exit(1)

    token = oauth["accessToken"]
    ok(f"accessToken: {token[:12]}…{token[-4:]} ({len(token)} chars)")

    # 3. expiry
    step(3, "เช็ค token expiry")
    exp = oauth.get("expiresAt")
    if exp:
        exp_dt = datetime.fromtimestamp(exp / 1000, tz=timezone.utc).astimezone()
        now = datetime.now().astimezone()
        if exp_dt > now:
            ok(f"ยังไม่หมดอายุ (หมด {exp_dt.strftime('%H:%M:%S')})")
        else:
            bad(f"หมดอายุแล้วตั้งแต่ {exp_dt.strftime('%Y-%m-%d %H:%M')}")
            print("   → เปิด Claude Code/รัน `claude` สักครั้งเพื่อ refresh token แล้วลองใหม่")
    else:
        print("    ⚠️ ไม่มี expiresAt — ลองยิง API ดูเลย")

    # 4. API call
    step(4, f"ยิง GET {USAGE_URL}")
    req = urllib.request.Request(
        USAGE_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-code/2.0.14",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
        ok("HTTP 200")
        print("\n    Raw response:")
        print("    " + json.dumps(data, indent=2).replace("\n", "\n    "))
        five = data.get("five_hour") or {}
        week = data.get("seven_day") or {}
        print(f"\n🎉 สรุป: ทุกอย่างทำงาน!")
        print(f"   5-hour: {five.get('utilization')}%  |  Weekly: {week.get('utilization')}%")
        print(f"   → เปิด widget ได้เลย: python3 claude_usage_widget.py")
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode()[:300]
        except Exception:
            pass
        bad(f"HTTP {e.code}")
        print(f"    body: {body}")
        if e.code in (401, 403):
            print("   → token ใช้ไม่ได้ — เปิด Claude Code สักครั้งเพื่อ refresh แล้วรัน doctor ใหม่")
        elif e.code == 429:
            print("   → โดน rate limit — รอ 5-15 นาทีแล้วลองใหม่ (อย่ายิงถี่)")
        sys.exit(1)
    except Exception as e:
        bad(f"{e}")
        print("   → เช็ค internet connection")
        sys.exit(1)


if __name__ == "__main__":
    main()
