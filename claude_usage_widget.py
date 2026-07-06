#!/usr/bin/env python3
"""
Claude Cat — macOS Menu Bar App (v2, OAuth API)

แสดง usage ของ Claude Pro/Max บน menu bar
ข้อมูลจาก endpoint เดียวกับคำสั่ง /usage ใน Claude Code (server-side, แม่นยำ)

วิธีทำงาน:
  1. อ่าน OAuth token ของ Claude Code จาก macOS Keychain
     (item: "Claude Code-credentials") → fallback ~/.claude/.credentials.json
  2. GET https://api.anthropic.com/api/oauth/usage ทุก 180 วินาที
  3. แสดง % ของ 5-hour window บน menu bar, รายละเอียดใน dropdown

เงื่อนไข: ต้องเคย login Claude Code (`claude`) ในเครื่องนี้อย่างน้อย 1 ครั้ง
ถ้ามีปัญหา: รัน  python3 claude_doctor.py  เพื่อดูว่าพังขั้นตอนไหน
"""

import json
import logging
import os
import subprocess
import threading
import urllib.request
import urllib.error
from datetime import datetime, timezone

import rumps

# ── constants ─────────────────────────────────────────────────────────────────

USAGE_URL        = "https://api.anthropic.com/api/oauth/usage"
USER_AGENT       = "claude-code/2.0.14"          # จำเป็น! ไม่ใส่ = โดน 429 ถาวร
BETA_HEADER      = "oauth-2025-04-20"
KEYCHAIN_SERVICE = "Claude Code-credentials"
CREDS_FILE       = os.path.expanduser("~/.claude/.credentials.json")
CACHE_FILE       = os.path.expanduser("~/.claude/.claudecat_cache.json")
LOG_FILE         = os.path.expanduser("~/.claude_widget.log")
ICON_PATH        = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "cat_icon.png")

POLL_SECONDS     = 180                           # ปลอดภัยตาม rate limit
BACKOFF_MAX      = 900                           # cap 15 นาที เมื่อโดน 429

logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("claude_cat")


# ── credentials ───────────────────────────────────────────────────────────────

class CredsError(Exception):
    """มีข้อความภาษาคนอ่านรู้เรื่อง สำหรับโชว์ในเมนู"""


# ── token cache ────────────────────────────────────────────────────────────────
# ปัญหา: Claude Code refresh token เป็นระยะ → สร้าง keychain item ใหม่ → ACL ที่กด
# "Always Allow" โดนล้าง → macOS เด้งถามรหัสทุกครั้งที่เราอ่าน keychain (ทุก 180s)
# วิธีแก้: cache token ที่อ่านได้ลงไฟล์ แล้วใช้ซ้ำจนกว่าจะใกล้หมดอายุ ค่อยแตะ keychain
# ใหม่ → ลดการอ่าน keychain จาก "ทุกรอบ poll" เหลือ "≈ ครั้งเดียวต่ออายุ token"

def _load_cache() -> dict | None:
    try:
        with open(CACHE_FILE) as f:
            oauth = json.load(f)
        if oauth.get("accessToken"):
            return oauth
    except Exception:
        pass
    return None


def _save_cache(oauth: dict) -> None:
    try:
        os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
        tmp = CACHE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(oauth, f)
        os.chmod(tmp, 0o600)
        os.replace(tmp, CACHE_FILE)
        log.info("creds: cached token to %s", CACHE_FILE)
    except Exception as e:
        log.warning("creds: cache write failed: %s", e)


def _read_keychain() -> dict | None:
    """อ่าน keychain ตรงๆ (อาจเด้ง popup) — return oauth dict หรือ None"""
    try:
        r = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode == 0 and r.stdout.strip():
            data = json.loads(r.stdout.strip())
            oauth = data.get("claudeAiOauth")
            if oauth and oauth.get("accessToken"):
                log.info("creds: loaded from Keychain")
                return oauth
            raise CredsError("Keychain item มี แต่ไม่มี accessToken ข้างใน")
        log.warning("creds: keychain returncode=%s stderr=%s", r.returncode, r.stderr.strip())
    except CredsError:
        raise
    except Exception as e:
        log.warning("creds: keychain read failed: %s", e)
    return None


def read_credentials() -> dict:
    """
    คืน dict claudeAiOauth: {accessToken, refreshToken, expiresAt(ms), ...}
    ลำดับ: env var → cache (ถ้า token ยังไม่ใกล้หมดอายุ) → Keychain → cache file → ~/.claude/.credentials.json
    raise CredsError ถ้าไม่เจอ
    การ cache ทำให้แตะ keychain เฉพาะตอน token ใกล้หมดอายุ → ลด popup ขอรหัส
    """
    env_token = os.environ.get("CLAUDE_CODE_OAUTH_TOKEN")
    if env_token:
        log.info("creds: using CLAUDE_CODE_OAUTH_TOKEN env var")
        return {"accessToken": env_token, "expiresAt": None}

    # 1) cache-first: ถ้า token ใน cache ยังใช้ได้ (ไม่ใกล้หมดอายุ) → ไม่ต้องแตะ keychain เลย
    cached = _load_cache()
    if cached and not token_expired(cached):
        log.info("creds: using cached token (keychain skipped)")
        return cached

    # 2) token หมด/ใกล้หมด หรือไม่มี cache → อ่าน keychain (อาจเด้ง popup ครั้งเดียว) แล้ว cache ไว้
    oauth = _read_keychain()
    if oauth:
        _save_cache(oauth)
        return oauth

    # 3) keychain อ่านไม่ได้ แต่ยังมี cache เก่า → ใช้ไปก่อน (เผื่อ token ยังพอใช้ได้)
    if cached:
        log.warning("creds: keychain unavailable, falling back to cached token")
        return cached

    # 4) fallback สุดท้าย: credentials file ของ Claude Code
    if os.path.exists(CREDS_FILE):
        with open(CREDS_FILE) as f:
            data = json.load(f)
        oauth = data.get("claudeAiOauth")
        if oauth and oauth.get("accessToken"):
            log.info("creds: loaded from %s", CREDS_FILE)
            _save_cache(oauth)
            return oauth

    raise CredsError("ไม่พบ credentials — ต้อง login Claude Code ก่อน (รัน `claude` ใน Terminal)")


def token_expired(oauth: dict) -> bool:
    exp = oauth.get("expiresAt")
    if not exp:
        return False
    # expiresAt = epoch milliseconds
    return (exp / 1000) < (datetime.now(timezone.utc).timestamp() + 60)


# ── API ───────────────────────────────────────────────────────────────────────

class ApiError(Exception):
    def __init__(self, msg, status=None):
        super().__init__(msg)
        self.status = status


def fetch_usage(access_token: str) -> dict:
    req = urllib.request.Request(
        USAGE_URL,
        headers={
            "Authorization": f"Bearer {access_token}",
            "anthropic-beta": BETA_HEADER,
            "User-Agent": USER_AGENT,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = resp.read().decode()
            log.info("api: 200 OK")
            return json.loads(body)
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode()[:300]
        except Exception:
            pass
        log.error("api: HTTP %s — %s", e.code, body)
        raise ApiError(f"HTTP {e.code}", status=e.code)
    except Exception as e:
        log.error("api: %s", e)
        raise ApiError(str(e))


# ── formatting ────────────────────────────────────────────────────────────────

def fmt_window(w: dict | None, label: str) -> str:
    """'5-hour:  33%  (resets 14:00)'"""
    if not w or w.get("utilization") is None:
        return f"{label}: —"
    pct = w["utilization"]
    reset = ""
    if w.get("resets_at"):
        try:
            dt = datetime.fromisoformat(w["resets_at"]).astimezone()
            now = datetime.now().astimezone()
            fmt = "%H:%M" if dt.date() == now.date() else "%a %H:%M"
            reset = f"  (resets {dt.strftime(fmt)})"
        except ValueError as e:
            log.warning("fmt: bad resets_at %r: %s", w.get("resets_at"), e)
    return f"{label}: {pct:.0f}%{reset}"


def title_for(pct: float | None, has_icon: bool) -> str:
    if pct is None:
        return "✓" if has_icon else "🐱 ✓"
    warn = "⚠️" if pct >= 80 else ""
    txt = f"{warn}{pct:.0f}%"
    return txt if has_icon else f"🐱 {txt}"


# ── app ───────────────────────────────────────────────────────────────────────

class ClaudeCatApp(rumps.App):
    def __init__(self):
        icon = ICON_PATH if os.path.exists(ICON_PATH) else None
        super().__init__("🐱" if not icon else "", icon=icon, quit_button="Quit")
        if icon:
            self.template = False

        self._5h     = rumps.MenuItem("5-hour: —")
        self._wk     = rumps.MenuItem("Weekly: —")
        self._opus   = rumps.MenuItem("Weekly Opus: —")
        self._sonnet = rumps.MenuItem("Weekly Sonnet: —")
        self._status = rumps.MenuItem("Status: starting…")
        self._upd    = rumps.MenuItem("Last updated: never")
        self.menu = [
            self._5h, self._wk, self._opus, self._sonnet,
            None,
            self._status, self._upd,
            rumps.MenuItem("🔄 Refresh Now", callback=self.on_refresh),
            None,
            rumps.MenuItem("📄 Open Log", callback=self.on_log),
            rumps.MenuItem("🌐 Open claude.ai Usage", callback=self.on_web),
        ]

        self._interval = POLL_SECONDS
        self._timer = rumps.Timer(self._tick, POLL_SECONDS)
        self._timer.start()
        threading.Thread(target=self.refresh, daemon=True).start()
        log.info("=== Claude Cat started ===")

    # ── core ──
    def refresh(self):
        try:
            oauth = read_credentials()
        except CredsError as e:
            self._fail("🔑", f"Status: {e}")
            return
        except Exception as e:
            log.exception("creds: unexpected")
            self._fail("✗", f"Status: creds error — {str(e)[:60]} (ดู log)")
            return

        if token_expired(oauth):
            self._fail("🔒", "Status: token หมดอายุ — เปิด Claude Code/Cowork สักครั้งแล้วกด Refresh")
            return

        try:
            data = fetch_usage(oauth["accessToken"])
        except ApiError as e:
            if e.status in (401, 403):
                self._fail("🔒", "Status: token ใช้ไม่ได้ (401) — เปิด Claude Code แล้วกด Refresh")
            elif e.status == 429:
                self._interval = min(self._interval * 2, BACKOFF_MAX)
                self._set_timer(self._interval)
                self._fail("⏳", f"Status: rate limited — รอ {self._interval//60} นาที")
            else:
                self._fail("✗", f"Status: {e} (ดู log: ~/.claude_widget.log)")
            return

        # success → reset backoff
        if self._interval != POLL_SECONDS:
            self._interval = POLL_SECONDS
            self._set_timer(POLL_SECONDS)

        five = data.get("five_hour")
        self._5h.title     = fmt_window(five, "5-hour")
        self._wk.title     = fmt_window(data.get("seven_day"), "Weekly")
        self._opus.title   = fmt_window(data.get("seven_day_opus"), "Weekly Opus")
        self._sonnet.title = fmt_window(data.get("seven_day_sonnet"), "Weekly Sonnet")
        self._status.title = "Status: ✅ OK"
        self._upd.title    = f"Last updated: {datetime.now().strftime('%H:%M:%S')}"
        pct = five.get("utilization") if five else None
        self.title = title_for(pct, os.path.exists(ICON_PATH))

    def _fail(self, badge, status_text):
        self.title = badge
        self._status.title = status_text
        log.warning("fail: %s", status_text)

    def _set_timer(self, seconds):
        try:
            self._timer.stop()
            self._timer = rumps.Timer(self._tick, seconds)
            self._timer.start()
        except Exception:
            log.exception("timer reset failed")

    # ── callbacks ──
    def _tick(self, _):
        threading.Thread(target=self.refresh, daemon=True).start()

    def on_refresh(self, _):
        threading.Thread(target=self.refresh, daemon=True).start()

    def on_log(self, _):
        subprocess.run(["open", LOG_FILE])

    def on_web(self, _):
        import webbrowser
        webbrowser.open("https://claude.ai/settings/usage")


if __name__ == "__main__":
    ClaudeCatApp().run()
