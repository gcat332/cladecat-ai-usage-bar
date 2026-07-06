# 🐱 ClaudeCat — Claude Usage Menu Bar Widget

Widget บน **macOS menu bar** ที่โชว์ usage ของ **Claude Pro/Max** (และ **Codex/ChatGPT**) แบบเรียลไทม์ — ดึงข้อมูลจาก endpoint เดียวกับคำสั่ง `/usage` ใน Claude Code จึงแม่นยำระดับ server-side

โปรเจกต์นี้มี **2 เวอร์ชัน** ให้เลือกใช้:

| เวอร์ชัน | ไฟล์หลัก | จุดเด่น |
|---------|----------|--------|
| **Python** | `claude_usage_widget.py` | ติดตั้งง่าย รันได้เลย (ใช้ `rumps`) — โชว์เฉพาะ Claude |
| **Swift (native `.app`)** | `ClaudeCatApp/main.swift` | แอปเนทีฟ ไอคอนอนิเมชัน เปลี่ยนไอคอนเองได้ รองรับทั้ง **Claude + Codex** |

---

## ✨ Features

- แสดง **% การใช้งาน** ของ 5-hour window บน menu bar
- Dropdown แสดงรายละเอียด: 5-hour, Weekly, Weekly Opus / Sonnet (Python) หรือ Claude + Codex (Swift)
- อ่าน OAuth token จาก **macOS Keychain** ของ Claude Code อัตโนมัติ (ไม่ต้อง paste token เอง)
- Refresh อัตโนมัติทุก 180 วินาที + ปุ่ม **Refresh Now**
- Cache token ลงไฟล์ เพื่อไม่ให้ macOS เด้งถามรหัส Keychain ทุกครั้ง
- Backoff อัตโนมัติเมื่อโดน rate limit (429)
- เวอร์ชัน Swift: ต่ออายุ access token เองผ่าน OAuth refresh โดยไม่ต้องเปิด Claude Code

---

## 📋 ข้อกำหนดเบื้องต้น (Requirements)

- macOS 12.0 ขึ้นไป
- Python 3 (สำหรับเวอร์ชัน Python)
- **เคย login Claude Code (`claude`) ในเครื่องนี้อย่างน้อย 1 ครั้ง** — เพราะ widget อ่าน OAuth credentials จาก Keychain item `"Claude Code-credentials"`
- เวอร์ชัน Swift ต้องมี Xcode Command Line Tools (`xcode-select --install`)

> **หมายเหตุ:** endpoint `/api/oauth/usage` ต้องการ scope `user:profile` ซึ่งมีเฉพาะใน login ปกติของ Claude Code — token ที่สร้างจาก `setup-token` ใช้ไม่ได้

---

## 🚀 วิธีใช้งาน

### เวอร์ชัน Python (แนะนำสำหรับเริ่มต้น)

```bash
# ติดตั้ง dependency แล้วรันเลย
./scripts/setup.sh
```

หรือดับเบิลคลิก `scripts/start_widget.command` เพื่อเปิด

ให้เปิดอัตโนมัติทุกครั้งที่ login:

```bash
./scripts/install_autostart.sh    # ติดตั้งเป็น LaunchAgent
```

### เวอร์ชัน Swift (native app)

```bash
./scripts/build_app.sh            # build ได้ ClaudeCat.app + (option) เพิ่มเข้า Login Items
open ClaudeCat.app
```

---

## 🩺 แก้ปัญหา (Troubleshooting)

ถ้า widget ไม่โชว์ข้อมูล ให้รัน doctor เพื่อดูว่าพังขั้นตอนไหน:

```bash
python3 claude_doctor.py            # เช็คทีละ step: Keychain → token → API
python3 claude_doctor_profiles.py   # เช็ค usage แยกตาม profile (claude-g / claude-m)
```

---

## 📁 โครงสร้างไฟล์

```
claude_usage_widget.py       # widget หลัก (Python / rumps)
claude_doctor.py             # เครื่องมือ diagnose
claude_doctor_profiles.py    # diagnose แยกตาม profile
ClaudeCatApp/
  ├─ main.swift              # ซอร์สแอปเนทีฟ (Claude + Codex)
  └─ Info.plist              # bundle config
scripts/
  ├─ build_app.sh            # build ClaudeCat.app
  ├─ setup.sh                # ติดตั้ง + รันเวอร์ชัน Python
  ├─ start_widget.command    # ดับเบิลคลิกเปิด
  └─ install_autostart.sh    # ตั้งให้เปิดอัตโนมัติตอน login
assets/                      # ไอคอน / รูปที่ใช้ตอน build และ runtime
```

---

## 🔒 ความเป็นส่วนตัว

Widget อ่าน OAuth token จาก Keychain ในเครื่องคุณเท่านั้น และเรียก API ไปที่ Anthropic (และ OpenAI สำหรับ Codex) โดยตรง — ไม่มีการส่งข้อมูลไป server อื่น token ถูก cache ไว้ที่ `~/.claude/.claudecat_cache.json` ในเครื่องคุณเอง

---

## ⚠️ Disclaimer

โปรเจกต์นี้เป็นเครื่องมือส่วนตัว ไม่ได้เป็นผลิตภัณฑ์ทางการของ Anthropic หรือ OpenAI และใช้ endpoint ที่ไม่เป็นทางการ (unofficial) ซึ่งอาจเปลี่ยนแปลงได้ทุกเมื่อ
