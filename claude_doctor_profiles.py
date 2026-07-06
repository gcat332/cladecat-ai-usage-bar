#!/usr/bin/env python3
"""
ตรวจ Claude usage แยกตาม profile (claude-g / claude-m) — เลียนแบบ logic ของ main.swift
รัน:  python3 claude_doctor_profiles.py
"""
import json, os, subprocess, urllib.request, urllib.error
from datetime import datetime, timezone

USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
KEYCHAIN_SERVICE = "Claude Code-credentials"
PROFILES = {
    "claude-g": "~/.claude-g/.credentials.json",
    "claude-m": "~/.claude-m/.credentials.json",
}

def read_keychain():
    try:
        r = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=30)
        if r.returncode == 0 and r.stdout.strip():
            return json.loads(r.stdout.strip()).get("claudeAiOauth")
    except Exception:
        pass
    return None

def check(name, rel):
    print(f"\n{'='*50}\nPROFILE: {name}   ({rel})")
    path = os.path.expanduser(rel)
    oauth, src = None, None
    if os.path.exists(path):
        try:
            oauth = json.load(open(path)).get("claudeAiOauth")
            src = "file"
            print(f"  ✅ เจอไฟล์ ({os.path.getsize(path)} bytes)")
        except Exception as e:
            print(f"  ❌ ไฟล์ parse ไม่ออก: {e}")
    else:
        print("  ❌ ไม่มีไฟล์ credentials")
        oauth = read_keychain()           # <-- เหมือน Swift: fallback ไป keychain เดียวกันทุก profile
        if oauth:
            src = "keychain (fallback ร่วมกันทุก profile!)"
            print("  ⚠️  ใช้ keychain fallback — ตัวนี้เป็น item เดียวร่วมกันทุก profile")

    if not oauth or not oauth.get("accessToken"):
        print("  💀 ไม่มี OAuth token → widget โชว์ error")
        return
    tok = oauth["accessToken"]
    print(f"  token({src}): {tok[:12]}…{tok[-4:]}")
    exp = oauth.get("expiresAt")
    if exp:
        dt = datetime.fromtimestamp(exp/1000, tz=timezone.utc).astimezone()
        state = "ยังไม่หมด" if dt > datetime.now().astimezone() else "❌ หมดอายุแล้ว (widget ไม่ refresh ให้ — เปิด Claude Code ของ profile นี้)"
        print(f"  expiry: {dt:%Y-%m-%d %H:%M}  → {state}")

    req = urllib.request.Request(USAGE_URL, headers={
        "Authorization": f"Bearer {tok}",
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-code/2.0.14",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            d = json.loads(r.read().decode())
        five = (d.get("five_hour") or {}).get("utilization")
        week = (d.get("seven_day") or {}).get("utilization")
        print(f"  🎉 HTTP 200 — 5h={five}%  weekly={week}%")
    except urllib.error.HTTPError as e:
        body = ""
        try: body = e.read().decode()[:200]
        except Exception: pass
        print(f"  ❌ HTTP {e.code}  body={body}")
        if e.code in (401, 403):
            print("     → token ใช้ไม่ได้/ไม่ตรง account — login profile นี้ใหม่")
    except Exception as e:
        print(f"  ❌ {e}")

if __name__ == "__main__":
    print("Claude Profiles Doctor")
    for n, p in PROFILES.items():
        check(n, p)
    print(f"\n{'='*50}\nหมายเหตุ: ถ้า claude-m ไม่มีไฟล์ แต่ claude-g มี → claude-m จะ fallback")
    print("ไปอ่าน keychain ของ claude-g แทน (บั๊ก) หรือ error เพราะ token คนละ account")
