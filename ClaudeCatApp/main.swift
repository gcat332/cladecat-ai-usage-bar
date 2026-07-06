// ClaudeCat — macOS menu bar app แสดง usage ของ Claude + Codex (5h / weekly %)
// Claude: api.anthropic.com/api/oauth/usage (เหมือน /usage ใน Claude Code)
//         อ่าน OAuth creds จาก Keychain (Claude Code login) — endpoint นี้ต้องการ scope user:profile
//         ซึ่ง setup-token ไม่มี จึงใช้ token แบบวางเองไม่ได้
// Codex : chatgpt.com/backend-api/wham/usage  (เหมือน CodexBar OAuth path)
// Build : ./scripts/build_app.sh   (ต้องมี Xcode Command Line Tools)

import Cocoa
import Security
import UniformTypeIdentifiers

// ── config ────────────────────────────────────────────────────────────────────

let claudeUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
let claudeUserAgent = "claude-code/2.1.138"   // จำเป็น — UA เก่าโดน 429 ถาวร (เช็ค npm เวอร์ชันล่าสุด)
let claudeBeta = "oauth-2025-04-20"
let claudeKeychainService = "Claude Code-credentials"

// OAuth refresh (Claude Code) — ค่าไม่ทางการ ใช้ต่ออายุ access token เองโดยไม่ต้องเปิด Claude Code
let claudeOAuthTokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
let claudeOAuthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

let codexUsageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
let codexUserAgent = "codex_cli_rs"
// OAuth refresh (Codex/ChatGPT) — ต่ออายุ access token เองโดยไม่ต้องรัน `codex`
// endpoint + client_id ตาม Codex CLI (body แบบ form-urlencoded)
let codexOAuthTokenURL = URL(string: "https://auth.openai.com/oauth/token")!
let codexOAuthClientID = "app_EMoamEEZ73f0CkXaXp7hrann"

let pollInterval: TimeInterval = 180
let backoffMax: TimeInterval = 900

let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude_cat.log")

// โฟลเดอร์เก็บ custom icon
let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("ClaudeCat")
let customIconURL = appSupportDir.appendingPathComponent("icon.png")

func log(_ msg: String) {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "\(f.string(from: Date())) \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile()
        h.write(data)
        try? h.close()
    } else {
        try? data.write(to: logURL)
    }
}

// ── models: Claude ──────────────────────────────────────────────────────────────

struct UsageWindow: Decodable {
    let utilization: Double?
    let resets_at: String?
}

struct ClaudeUsageResponse: Decodable {
    let five_hour: UsageWindow?
    let seven_day: UsageWindow?
}

struct OAuthCreds: Decodable {
    let accessToken: String
    let expiresAt: Double?
}

struct CredsFile: Decodable {
    let claudeAiOauth: OAuthCreds?
}

struct OAuthRefreshResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?     // seconds
}

enum CredSource {
    case keychain
    case file(URL)
}

// ── models: Codex ───────────────────────────────────────────────────────────────

struct CodexTokens: Decodable {
    let access_token: String?
    let account_id: String?
}

struct CodexAuthFile: Decodable {
    let tokens: CodexTokens?
}

struct CodexWindow: Decodable {
    let used_percent: Double?
    let reset_at: Double?            // unix seconds
    let limit_window_seconds: Double?
}

struct CodexRateLimit: Decodable {
    let primary_window: CodexWindow?    // 5-hour / session
    let secondary_window: CodexWindow?  // weekly
}

struct CodexUsageResponse: Decodable {
    let rate_limit: CodexRateLimit?
}

struct CodexRefreshResponse: Decodable {
    let access_token: String?
    let id_token: String?
    let refresh_token: String?
}

// ── credentials: Claude ─────────────────────────────────────────────────────────
// บน macOS Claude Code เก็บ OAuth creds ไว้ใน Keychain (item เดียว) และ refresh ให้เอง
// เมื่อรัน Claude Code → อ่าน Keychain เป็นหลัก, fallback ไฟล์ ~/.claude/.credentials.json
// (กรณี SSH/Linux หรือ export มาเอง)

/// อ่าน creds ดิบ + บอกว่ามาจาก Keychain หรือไฟล์ (ไว้เขียน token ใหม่กลับที่เดิม)
func loadClaudeCredsRaw() -> (data: Data, source: CredSource)? {
    // 1) macOS Keychain (source หลัก)
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: claudeKeychainService,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
        return (data, .keychain)
    }
    // 2) fallback: ~/.claude/.credentials.json
    let credsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/.credentials.json")
    if let data = try? Data(contentsOf: credsURL) {
        return (data, .file(credsURL))
    }
    return nil
}

/// เขียน creds (ทั้งก้อน JSON) กลับไปที่ source เดิม
func saveClaudeCredsRaw(_ data: Data, to source: CredSource) {
    switch source {
    case .keychain:
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: claudeKeychainService,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status != errSecSuccess { log("claude refresh: keychain update failed (\(status))") }
    case .file(let url):
        try? data.write(to: url)
    }
}

func readClaudeCredentials() -> (creds: OAuthCreds?, error: String?) {
    // อ่านจาก Keychain (Claude Code login) → fallback ~/.claude/.credentials.json — refresh ได้
    guard let (data, _) = loadClaudeCredsRaw(),
          let parsed = try? JSONDecoder().decode(CredsFile.self, from: data),
          let oauth = parsed.claudeAiOauth else {
        return (nil, "ไม่พบ creds — เปิด Claude Code / login ก่อน")
    }
    return (oauth, nil)
}

/// ต่ออายุ access token ด้วย refresh token → เขียนกลับ Keychain/ไฟล์ → คืน creds ใหม่
func refreshClaudeToken(completion: @escaping (OAuthCreds?, String?) -> Void) {
    guard let (data, source) = loadClaudeCredsRaw(),
          var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          var oauth = root["claudeAiOauth"] as? [String: Any],
          let refreshToken = oauth["refreshToken"] as? String, !refreshToken.isEmpty else {
        completion(nil, "ไม่มี refresh token ใน creds")
        return
    }

    var req = URLRequest(url: claudeOAuthTokenURL, timeoutInterval: 20)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(claudeUserAgent, forHTTPHeaderField: "User-Agent")
    let body: [String: Any] = [
        "grant_type": "refresh_token",
        "refresh_token": refreshToken,
        "client_id": claudeOAuthClientID,
    ]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)

    URLSession.shared.dataTask(with: req) { data, resp, error in
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil, code == 200, let data = data,
              let r = try? JSONDecoder().decode(OAuthRefreshResponse.self, from: data) else {
            let b = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            log("claude refresh: HTTP \(code) — \(String(b.prefix(200)))")
            completion(nil, "refresh ล้มเหลว (HTTP \(code))")
            return
        }
        // อัปเดตเฉพาะ field ที่เกี่ยว เก็บ field อื่น (scopes/subscriptionType) ไว้
        let newExpMs = (Date().timeIntervalSince1970 + (r.expires_in ?? 3600)) * 1000
        oauth["accessToken"] = r.access_token
        if let rt = r.refresh_token, !rt.isEmpty { oauth["refreshToken"] = rt }
        oauth["expiresAt"] = newExpMs
        root["claudeAiOauth"] = oauth
        if let out = try? JSONSerialization.data(withJSONObject: root) {
            saveClaudeCredsRaw(out, to: source)
        }
        log("claude refresh: 200 OK — token ใหม่ (exp +\(Int(r.expires_in ?? 3600))s)")
        completion(OAuthCreds(accessToken: r.access_token, expiresAt: newExpMs), nil)
    }.resume()
}

func claudeTokenExpired(_ creds: OAuthCreds) -> Bool {
    guard let exp = creds.expiresAt else { return false }
    return Date(timeIntervalSince1970: exp / 1000) < Date().addingTimeInterval(60)
}

// ── credentials: Codex ──────────────────────────────────────────────────────────

/// $CODEX_HOME/auth.json → ~/.codex/auth.json
func codexAuthURL() -> URL {
    if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
        return URL(fileURLWithPath: home).appendingPathComponent("auth.json")
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/auth.json")
}

func readCodexCredentials() -> (token: String?, accountId: String?, error: String?) {
    guard let data = try? Data(contentsOf: codexAuthURL()) else {
        return (nil, nil, "login Codex ก่อน (รัน `codex`)")
    }
    guard let parsed = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
          let token = parsed.tokens?.access_token, !token.isEmpty else {
        return (nil, nil, "auth.json parse ไม่ออก")
    }
    return (token, parsed.tokens?.account_id, nil)
}

/// encode dict เป็น application/x-www-form-urlencoded (OpenAI token endpoint ต้องการแบบนี้)
func formURLEncoded(_ params: [String: String]) -> Data? {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let pairs = params.map { k, v -> String in
        let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
        let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
        return "\(ek)=\(ev)"
    }
    return pairs.joined(separator: "&").data(using: .utf8)
}

/// ต่ออายุ Codex access token ด้วย refresh_token → เขียนกลับ auth.json → คืน token ใหม่
func refreshCodexToken(completion: @escaping (String?, String?, String?) -> Void) {
    let url = codexAuthURL()
    guard let data = try? Data(contentsOf: url),
          var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          var tokens = root["tokens"] as? [String: Any],
          let refreshToken = tokens["refresh_token"] as? String, !refreshToken.isEmpty else {
        completion(nil, nil, "ไม่มี refresh token ใน auth.json")
        return
    }
    let accountId = tokens["account_id"] as? String

    var req = URLRequest(url: codexOAuthTokenURL, timeoutInterval: 20)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.httpBody = formURLEncoded([
        "grant_type": "refresh_token",
        "refresh_token": refreshToken,
        "client_id": codexOAuthClientID,
    ])

    URLSession.shared.dataTask(with: req) { data, resp, error in
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil, (200..<300).contains(code), let data = data,
              let r = try? JSONDecoder().decode(CodexRefreshResponse.self, from: data),
              let newAccess = r.access_token, !newAccess.isEmpty else {
            let b = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            log("codex refresh: HTTP \(code) — \(String(b.prefix(200)))")
            completion(nil, nil, "refresh ล้มเหลว (HTTP \(code))")
            return
        }
        tokens["access_token"] = newAccess
        if let idt = r.id_token, !idt.isEmpty { tokens["id_token"] = idt }
        if let rt = r.refresh_token, !rt.isEmpty { tokens["refresh_token"] = rt }
        root["tokens"] = tokens
        root["last_refresh"] = ISO8601DateFormatter().string(from: Date())
        if let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) {
            try? out.write(to: url)
        }
        log("codex refresh: 200 OK — token ใหม่")
        completion(newAccess, accountId, nil)
    }.resume()
}

// ── helpers ───────────────────────────────────────────────────────────────────

func parseISO(_ s: String) -> Date? {
    let cleaned = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    return ISO8601DateFormatter().date(from: cleaned)
}

func resetSuffix(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let f = DateFormatter()
    f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "EEE HH:mm"
    return "  (resets \(f.string(from: d)))"
}

/// Claude window → "label: 33%  (resets 14:00)"
func fmtClaude(_ w: UsageWindow?, _ label: String) -> String {
    guard let w = w, let pct = w.utilization else { return "\(label): —" }
    let d = w.resets_at.flatMap(parseISO)
    return String(format: "%@: %.0f%%%@", label, pct, resetSuffix(d))
}

/// Codex window → "label: 33%  (resets 14:00)"
func fmtCodex(_ w: CodexWindow?, _ label: String) -> String {
    guard let w = w, let pct = w.used_percent else { return "\(label): —" }
    let d = w.reset_at.map { Date(timeIntervalSince1970: $0) }
    return String(format: "%@: %.0f%%%@", label, pct, resetSuffix(d))
}

// ── app ───────────────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var interval = pollInterval
    var lastPct: Double?   // Claude 5h % → ใช้โชว์ข้างไอคอน
    var claudeRefreshAttempted = false   // กัน loop เวลา refresh token แล้วยัง 401
    var codexRefreshAttempted = false    // เช่นเดียวกันฝั่ง Codex

    // อนิเมชันไอคอนเมนูบาร์ (วนเฟรม เพราะ NSStatusItem ไม่เล่น .gif เอง)
    var iconAnimTimer: Timer?
    var iconAnimFrames: [NSImage] = []
    var iconAnimIndex = 0
    let iconAnimFrameNames = ["cute2", "cute3"]
    let iconAnimInterval: TimeInterval = 0.5

    var showPercent: Bool {
        get { UserDefaults.standard.object(forKey: "showPercent") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "showPercent") }
    }

    let itemClaude5h = NSMenuItem(title: "5 hours: —", action: nil, keyEquivalent: "")
    let itemClaudeWk = NSMenuItem(title: "weekly: —", action: nil, keyEquivalent: "")
    let itemCodex5h  = NSMenuItem(title: "5 hours: —", action: nil, keyEquivalent: "")
    let itemCodexWk  = NSMenuItem(title: "weekly: —", action: nil, keyEquivalent: "")
    let itemStatus   = NSMenuItem(title: "status: starting…", action: nil, keyEquivalent: "")
    let itemUpd      = NSMenuItem(title: "last updated: never", action: nil, keyEquivalent: "")
    var itemShowPct: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()   // ทำให้ Cmd+C/V/X/A ใช้ได้ในช่องกรอก token
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyIcon()

        // โลโก้แทนชื่อ provider (template = ปรับสีตาม light/dark เอง)
        let claudeLogo = bundledImage("claude_logo", template: false)  // colored app-icon
        let codexLogo  = bundledImage("codex_logo", template: false)   // Codex blue (#5D74FF)
        itemClaude5h.image = claudeLogo
        itemClaudeWk.image = claudeLogo
        itemCodex5h.image  = codexLogo
        itemCodexWk.image  = codexLogo

        let menu = NSMenu()
        menu.addItem(itemClaude5h)
        menu.addItem(itemClaudeWk)
        menu.addItem(itemCodex5h)
        menu.addItem(itemCodexWk)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(itemStatus)
        menu.addItem(itemUpd)
        menu.addItem(makeItem("🔄 refresh now", #selector(refreshNow)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeSettingsMenu())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem("quit", #selector(quit)))
        statusItem.menu = menu

        log("=== ClaudeCat (Swift, Claude+Codex) started ===")
        refresh()
        startTimer(pollInterval)
    }

    /// แอปแบบ .accessory ไม่มี main menu → Cmd+V/C/X/A ในช่องกรอกใช้ไม่ได้
    /// สร้าง Edit menu ให้ ระบบจะ dispatch คีย์ลัดผ่าน responder chain เข้า field editor เอง
    func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (ต้องเป็น item แรกเสมอ)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // Edit menu — ปลดล็อก Cut/Copy/Paste/Select All
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    func makeItem(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    func makeSettingsMenu() -> NSMenuItem {
        let settingsItem = NSMenuItem(title: "⚙️ settings", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        // ── 📊 Show % ──
        itemShowPct = NSMenuItem(title: "📊 show %", action: #selector(togglePercent), keyEquivalent: "")
        itemShowPct.target = self
        itemShowPct.state = showPercent ? .on : .off
        sub.addItem(itemShowPct)

        // ── 🖼️ Icon ▶ ──
        let iconItem = NSMenuItem(title: "🖼️ icon", action: nil, keyEquivalent: "")
        let iconSub = NSMenu()
        iconSub.addItem(makeItem("🖼️ change icon…", #selector(changeIcon)))
        iconSub.addItem(makeItem("↩️ reset",         #selector(resetIcon)))
        iconItem.submenu = iconSub
        sub.addItem(iconItem)

        settingsItem.submenu = sub
        return settingsItem
    }

    /// โหลดโลโก้จาก bundle → ขนาดพอดีกับข้อความเมนู
    /// template=true → ปรับขาว/ดำตามธีม (โลโก้เส้นสีเดียว)
    /// template=false → คงสีจริง (โลโก้แบบ app icon มีพื้นหลังสี)
    func bundledImage(_ name: String, template: Bool) -> NSImage? {
        guard let path = Bundle.main.path(forResource: name, ofType: "png"),
              let img = NSImage(contentsOfFile: path) else { return nil }
        img.size = NSSize(width: 15, height: 15)
        img.isTemplate = template
        return img
    }

    func startTimer(_ seconds: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // ── icon ──
    func applyIcon() {
        // 1) custom icon (ผู้ใช้เลือกเอง) มาก่อน → static ไม่ animate
        if let custom = NSImage(contentsOf: customIconURL) {
            stopIconAnimation()
            custom.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = custom
            statusItem.button?.imagePosition = .imageLeft
            updateTitle()
            return
        }
        // 2) default: อนิเมชันแมวยูนิคอร์น 2 เฟรม
        loadIconAnimFrames()
        if iconAnimFrames.isEmpty {
            // 3) fallback: cat_icon.png นิ่ง ๆ
            stopIconAnimation()
            if let path = Bundle.main.path(forResource: "cat_icon", ofType: "png"),
               let img = NSImage(contentsOfFile: path) {
                img.size = NSSize(width: 18, height: 18)
                statusItem.button?.image = img
                statusItem.button?.imagePosition = .imageLeft
            } else {
                statusItem.button?.image = nil
            }
        } else {
            startIconAnimation()
        }
        updateTitle()
    }

    func loadIconAnimFrames() {
        iconAnimFrames = iconAnimFrameNames.compactMap { name in
            guard let path = Bundle.main.path(forResource: name, ofType: "png"),
                  let img = NSImage(contentsOfFile: path) else { return nil }
            img.size = NSSize(width: 18, height: 18)
            return img
        }
    }

    func startIconAnimation() {
        stopIconAnimation()
        guard !iconAnimFrames.isEmpty else { return }
        iconAnimIndex = 0
        statusItem.button?.image = iconAnimFrames[0]
        statusItem.button?.imagePosition = .imageLeft
        guard iconAnimFrames.count > 1 else { return }   // เฟรมเดียว → นิ่ง
        iconAnimTimer = Timer.scheduledTimer(withTimeInterval: iconAnimInterval, repeats: true) { [weak self] _ in
            guard let self = self, !self.iconAnimFrames.isEmpty else { return }
            self.iconAnimIndex = (self.iconAnimIndex + 1) % self.iconAnimFrames.count
            self.statusItem.button?.image = self.iconAnimFrames[self.iconAnimIndex]
        }
    }

    func stopIconAnimation() {
        iconAnimTimer?.invalidate()
        iconAnimTimer = nil
    }

    func updateTitle() {
        let hasIcon = statusItem.button?.image != nil
        guard let pct = lastPct else {
            statusItem.button?.title = hasIcon ? "" : "🐱"
            return
        }
        if showPercent {
            let warn = pct >= 80 ? "⚠️" : ""
            statusItem.button?.title = String(format: "%@%.0f%%", warn, pct)
        } else {
            statusItem.button?.title = pct >= 80 ? "⚠️" : (hasIcon ? "" : "🐱")
        }
    }

    // ── refresh: เรียกทั้งสอง provider ──
    func refresh() {
        refreshClaude()
        refreshCodex()
    }

    func markUpdated() {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        itemUpd.title = "last updated: \(f.string(from: Date()))"
    }

    // ── Claude ──
    func refreshClaude() {
        claudeRefreshAttempted = false
        let (creds, err) = readClaudeCredentials()
        guard let creds = creds else {
            itemClaude5h.title = "5 hours: 🔑 \(err ?? "creds error")"
            itemClaudeWk.title = "weekly: —"
            lastPct = nil; updateTitle()
            return
        }
        if claudeTokenExpired(creds) {
            // token หมดอายุ → ลองต่ออายุเองด้วย refresh token ก่อน
            claudeRefreshAttempted = true
            itemClaude5h.title = "5 hours: 🔄 ต่ออายุ token…"
            refreshClaudeToken { [weak self] newCreds, rerr in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let nc = newCreds {
                        self.fetchClaudeUsage(nc)
                    } else {
                        self.itemClaude5h.title = "5 hours: 🔒 token หมดอายุ"
                        self.itemClaudeWk.title = "weekly: —"
                        if let rerr = rerr { log("claude: \(rerr)") }
                    }
                }
            }
            return
        }
        fetchClaudeUsage(creds)
    }

    func fetchClaudeUsage(_ creds: OAuthCreds) {
        var req = URLRequest(url: claudeUsageURL, timeoutInterval: 15)
        req.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(claudeBeta, forHTTPHeaderField: "anthropic-beta")
        req.setValue(claudeUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, error in
            DispatchQueue.main.async {
                self?.handleClaude(data: data, resp: resp, error: error)
            }
        }.resume()
    }

    func handleClaude(data: Data?, resp: URLResponse?, error: Error?) {
        if let error = error {
            itemClaude5h.title = "5 hours: ✗ network"
            log("claude api: \(error.localizedDescription)")
            return
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if code == 401 || code == 403 {
            // token ถูกปฏิเสธ → ลอง refresh หนึ่งครั้งแล้วยิงใหม่
            if !claudeRefreshAttempted {
                claudeRefreshAttempted = true
                log("claude api: HTTP \(code) → ลอง refresh token — body[:300]=\(String(body.prefix(300)))")
                itemClaude5h.title = "5 hours: 🔄 ต่ออายุ token…"
                refreshClaudeToken { [weak self] nc, _ in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if let nc = nc {
                            self.fetchClaudeUsage(nc)
                        } else {
                            self.itemClaude5h.title = body.contains("scope")
                                ? "5 hours: 🔒 token scope ไม่พอ (ใช้ Keychain)"
                                : "5 hours: 🔒 token หมดอายุ"
                            self.itemClaudeWk.title = "weekly: —"
                        }
                    }
                }
                return
            }
            itemClaude5h.title = body.contains("scope")
                ? "5 hours: 🔒 token scope ไม่พอ (ใช้ Keychain)"
                : "5 hours: 🔒 token หมดอายุ"
            itemClaudeWk.title = "weekly: —"
            log("claude api: HTTP \(code) — body[:300]=\(String(body.prefix(300)))")
            return
        }
        if code == 429 {
            // เคารพ Retry-After จาก server ถ้ามี ไม่งั้นค่อย backoff เท่าตัว
            let retryAfter = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if let ra = retryAfter, let secs = Double(ra) {
                interval = min(max(secs + 15, pollInterval), 3600)   // เคารพ Retry-After เต็ม (+buffer) เพดาน 1 ชม.
            } else {
                interval = min(interval * 2, backoffMax)
            }
            startTimer(interval)
            itemClaude5h.title = "5 hours: ⏳ rate limited"
            log("claude api: 429 retry-after=\(retryAfter ?? "-") next=\(Int(interval))s — body[:300]=\(String(body.prefix(300)))")
            return
        }
        guard code == 200, let data = data,
              let usage = try? JSONDecoder().decode(ClaudeUsageResponse.self, from: data) else {
            itemClaude5h.title = "5 hours: ✗ HTTP \(code)"
            log("claude api: HTTP \(code) decode failed")
            return
        }

        if interval != pollInterval {
            interval = pollInterval
            startTimer(pollInterval)
        }
        claudeRefreshAttempted = false
        itemClaude5h.title = fmtClaude(usage.five_hour, "5 hours")
        itemClaudeWk.title = fmtClaude(usage.seven_day, "weekly")
        itemStatus.title = "status: ✅ OK"
        markUpdated()
        lastPct = usage.five_hour?.utilization
        updateTitle()
        log("claude api: 200 OK")
    }

    // ── Codex ──
    func refreshCodex() {
        codexRefreshAttempted = false
        let (token, accountId, err) = readCodexCredentials()
        guard let token = token else {
            itemCodex5h.title = "5 hours: 🔑 \(err ?? "creds error")"
            itemCodexWk.title = "weekly: —"
            return
        }
        fetchCodexUsage(token: token, accountId: accountId)
    }

    func fetchCodexUsage(token: String, accountId: String?) {
        var req = URLRequest(url: codexUsageURL, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(codexUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let acc = accountId, !acc.isEmpty {
            req.setValue(acc, forHTTPHeaderField: "chatgpt-account-id")
        }

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, error in
            DispatchQueue.main.async {
                self?.handleCodex(data: data, resp: resp, error: error)
            }
        }.resume()
    }

    func handleCodex(data: Data?, resp: URLResponse?, error: Error?) {
        if let error = error {
            itemCodex5h.title = "5 hours: ✗ network"
            log("codex api: \(error.localizedDescription)")
            return
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if code == 401 || code == 403 {
            // token หมดอายุ → ลอง refresh ด้วย refresh_token หนึ่งครั้งแล้วยิงใหม่
            if !codexRefreshAttempted {
                codexRefreshAttempted = true
                log("codex api: HTTP \(code) → ลอง refresh token")
                itemCodex5h.title = "5 hours: 🔄 ต่ออายุ token…"
                refreshCodexToken { [weak self] token, accountId, rerr in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if let token = token {
                            self.fetchCodexUsage(token: token, accountId: accountId)
                        } else {
                            self.itemCodex5h.title = "5 hours: 🔒 (\(code)) เปิด codex"
                            self.itemCodexWk.title = "weekly: —"
                            if let rerr = rerr { log("codex: \(rerr)") }
                        }
                    }
                }
                return
            }
            itemCodex5h.title = "5 hours: 🔒 (\(code)) เปิด codex"
            itemCodexWk.title = "weekly: —"
            log("codex api: HTTP \(code) — body[:300]=\(String(body.prefix(300)))")
            return
        }
        guard code == 200, let data = data,
              let usage = try? JSONDecoder().decode(CodexUsageResponse.self, from: data) else {
            itemCodex5h.title = "5 hours: ✗ HTTP \(code)"
            log("codex api: HTTP \(code) decode failed — body[:300]=\(String(body.prefix(300)))")
            return
        }

        codexRefreshAttempted = false
        itemCodex5h.title = fmtCodex(usage.rate_limit?.primary_window, "5 hours")
        itemCodexWk.title = fmtCodex(usage.rate_limit?.secondary_window, "weekly")
        itemStatus.title = "status: ✅ OK"
        markUpdated()
        log("codex api: 200 OK")
    }

    // ── actions ──
    @objc func refreshNow() { refresh() }

    @objc func togglePercent() {
        showPercent.toggle()
        itemShowPct.state = showPercent ? .on : .off
        updateTitle()
    }

    @objc func changeIcon() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "เลือกรูปไอคอน (png/jpg แนะนำสี่เหลี่ยมจัตุรัส)"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let src = panel.url {
            do {
                try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
                if let img = NSImage(contentsOf: src),
                   let tiff = img.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try png.write(to: customIconURL)
                    applyIcon()
                    log("icon: changed to \(src.lastPathComponent)")
                } else {
                    log("icon: read failed")
                }
            } catch {
                log("icon: save failed — \(error.localizedDescription)")
            }
        }
    }

    @objc func resetIcon() {
        try? FileManager.default.removeItem(at: customIconURL)
        applyIcon()
        log("icon: reset to default")
    }

    @objc func quit() { NSApplication.shared.terminate(nil) }
}

// ── entry point ───────────────────────────────────────────────────────────────

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
