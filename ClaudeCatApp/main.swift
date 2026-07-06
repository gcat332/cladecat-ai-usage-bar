// ClaudeCat — macOS menu bar app แสดง usage ของ Claude + Codex (5h / weekly %)
// Build : ./scripts/build_app.sh   (ต้องมี Xcode Command Line Tools)

import Cocoa
import UniformTypeIdentifiers

// ── app ───────────────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var claudeTimer: Timer?
    var codexTimer: Timer?
    var claudeState = ProviderRefreshState(
        baseInterval: pollInterval,
        maxInterval: backoffMax,
        cooldownUntil: UserDefaults.standard.object(forKey: claudeRefreshCooldownUntilKey) as? Date
    )
    var codexState = ProviderRefreshState(baseInterval: pollInterval, maxInterval: backoffMax)
    var lastPct: Double?   // Claude 5h % → ใช้โชว์ข้างไอคอน

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
        startClaudeTimer(claudeState.interval)
        startCodexTimer(codexState.interval)
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

    func startClaudeTimer(_ seconds: TimeInterval) {
        claudeTimer?.invalidate()
        claudeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            self?.refreshClaude()
        }
    }

    func startCodexTimer(_ seconds: TimeInterval) {
        codexTimer?.invalidate()
        codexTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            self?.refreshCodex()
        }
    }

    func saveClaudeCooldown() {
        if let until = claudeState.cooldownUntil {
            UserDefaults.standard.set(until, forKey: claudeRefreshCooldownUntilKey)
        } else {
            UserDefaults.standard.removeObject(forKey: claudeRefreshCooldownUntilKey)
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
        guard claudeState.beginRefresh() else {
            if let until = claudeState.cooldownUntil {
                let remaining = max(0, Int(until.timeIntervalSinceNow))
                itemClaude5h.title = "5 hours: ⏳ refresh rate limited"
                log("claude refresh: skipped during cooldown, \(remaining)s remaining")
            } else {
                log("claude refresh: skipped because previous refresh is still running")
            }
            return
        }
        let (creds, err) = readClaudeCredentials()
        guard let creds = creds else {
            itemClaude5h.title = "5 hours: 🔑 \(err ?? "creds error")"
            itemClaudeWk.title = "weekly: —"
            lastPct = nil; updateTitle()
            claudeState.finishRefresh()
            return
        }
        if claudeTokenExpired(creds) {
            // token หมดอายุ → ลองต่ออายุเองด้วย refresh token ก่อน
            claudeState.markTokenRefreshAttempted()
            itemClaude5h.title = "5 hours: 🔄 ต่ออายุ token…"
            refreshClaudeToken { [weak self] newCreds, rerr in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let nc = newCreds {
                        self.fetchClaudeUsage(nc)
                    } else {
                        if self.fetchFreshClaudeCredentialsAfterRateLimit(rerr) {
                            return
                        }
                        if !self.applyClaudeRefreshFailure(rerr) {
                            self.itemClaude5h.title = "5 hours: 🔒 token หมดอายุ"
                            if let rerr = rerr { log("claude: \(rerr.message)") }
                        }
                        self.itemClaudeWk.title = "weekly: —"
                        self.claudeState.finishRefresh()
                    }
                }
            }
            return
        }
        fetchClaudeUsage(creds)
    }

    func fetchFreshClaudeCredentialsAfterRateLimit(_ failure: OAuthRefreshFailure?) -> Bool {
        guard failure?.statusCode == 429 else { return false }
        let (freshCreds, freshErr) = readClaudeCredentials(skipCache: true)
        guard let freshCreds, !claudeTokenExpired(freshCreds) else {
            if let freshErr = freshErr { log("claude refresh: fresh credential fallback unavailable — \(freshErr)") }
            return false
        }
        log("claude refresh: using fresh credentials from Keychain/file after refresh 429")
        fetchClaudeUsage(freshCreds)
        return true
    }

    func applyClaudeRefreshFailure(_ failure: OAuthRefreshFailure?) -> Bool {
        guard let failure,
              let next = claudeState.applyTokenRefreshFailure(statusCode: failure.statusCode, retryAfter: failure.retryAfter) else {
            return false
        }
        saveClaudeCooldown()
        startClaudeTimer(next)
        itemClaude5h.title = "5 hours: ⏳ refresh rate limited"
        log("claude: \(failure.message), next refresh in \(Int(next))s")
        return true
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
            claudeState.finishRefresh()
            return
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if code == 401 || code == 403 {
            // token ถูกปฏิเสธ → ลอง refresh หนึ่งครั้งแล้วยิงใหม่
            if !claudeState.didAttemptTokenRefresh {
                claudeState.markTokenRefreshAttempted()
                log("claude api: HTTP \(code) → ลอง refresh token — body[:300]=\(String(body.prefix(300)))")
                itemClaude5h.title = "5 hours: 🔄 ต่ออายุ token…"
                refreshClaudeToken { [weak self] nc, failure in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if let nc = nc {
                            self.fetchClaudeUsage(nc)
                        } else {
                            if self.fetchFreshClaudeCredentialsAfterRateLimit(failure) {
                                return
                            }
                            if !self.applyClaudeRefreshFailure(failure) {
                                self.itemClaude5h.title = body.contains("scope")
                                    ? "5 hours: 🔒 token scope ไม่พอ (ใช้ Keychain)"
                                    : "5 hours: 🔒 token หมดอายุ"
                            }
                            self.itemClaudeWk.title = "weekly: —"
                            self.claudeState.finishRefresh()
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
            claudeState.finishRefresh()
            return
        }
        if code == 429 {
            // เคารพ Retry-After จาก server ถ้ามี ไม่งั้นค่อย backoff เท่าตัว
            let retryAfter = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let next = claudeState.applyRateLimit(retryAfter: retryAfter.flatMap(Double.init))
            startClaudeTimer(next)
            itemClaude5h.title = "5 hours: ⏳ rate limited"
            log("claude api: 429 retry-after=\(retryAfter ?? "-") next=\(Int(next))s — body[:300]=\(String(body.prefix(300)))")
            claudeState.finishRefresh()
            return
        }
        guard code == 200, let data = data,
              let usage = try? JSONDecoder().decode(ClaudeUsageResponse.self, from: data) else {
            itemClaude5h.title = "5 hours: ✗ HTTP \(code)"
            log("claude api: HTTP \(code) decode failed")
            claudeState.finishRefresh()
            return
        }

        if claudeState.interval != pollInterval || claudeState.cooldownUntil != nil {
            claudeState.resetInterval()
            saveClaudeCooldown()
            startClaudeTimer(claudeState.interval)
        }
        itemClaude5h.title = fmtClaude(usage.five_hour, "5 hours")
        itemClaudeWk.title = fmtClaude(usage.seven_day, "weekly")
        itemStatus.title = "status: ✅ OK"
        markUpdated()
        lastPct = usage.five_hour?.utilization
        updateTitle()
        log("claude api: 200 OK")
        claudeState.finishRefresh()
    }

    // ── Codex ──
    func refreshCodex() {
        guard codexState.beginRefresh() else {
            log("codex refresh: skipped because previous refresh is still running")
            return
        }
        let (token, accountId, err) = readCodexCredentials()
        guard let token = token else {
            itemCodex5h.title = "5 hours: 🔑 \(err ?? "creds error")"
            itemCodexWk.title = "weekly: —"
            codexState.finishRefresh()
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
            codexState.finishRefresh()
            return
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if code == 401 || code == 403 {
            // token หมดอายุ → ลอง refresh ด้วย refresh_token หนึ่งครั้งแล้วยิงใหม่
            if !codexState.didAttemptTokenRefresh {
                codexState.markTokenRefreshAttempted()
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
                            self.codexState.finishRefresh()
                        }
                    }
                }
                return
            }
            itemCodex5h.title = "5 hours: 🔒 (\(code)) เปิด codex"
            itemCodexWk.title = "weekly: —"
            log("codex api: HTTP \(code) — body[:300]=\(String(body.prefix(300)))")
            codexState.finishRefresh()
            return
        }
        if code == 429 {
            let retryAfter = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
            let next = codexState.applyRateLimit(retryAfter: retryAfter.flatMap(Double.init))
            startCodexTimer(next)
            itemCodex5h.title = "5 hours: ⏳ rate limited"
            log("codex api: 429 retry-after=\(retryAfter ?? "-") next=\(Int(next))s — body[:300]=\(String(body.prefix(300)))")
            codexState.finishRefresh()
            return
        }
        guard code == 200, let data = data,
              let usage = try? JSONDecoder().decode(CodexUsageResponse.self, from: data) else {
            itemCodex5h.title = "5 hours: ✗ HTTP \(code)"
            log("codex api: HTTP \(code) decode failed — body[:300]=\(String(body.prefix(300)))")
            codexState.finishRefresh()
            return
        }

        if codexState.interval != pollInterval {
            codexState.resetInterval()
            startCodexTimer(codexState.interval)
        }
        itemCodex5h.title = fmtCodex(usage.rate_limit?.primary_window, "5 hours")
        itemCodexWk.title = fmtCodex(usage.rate_limit?.secondary_window, "weekly")
        itemStatus.title = "status: ✅ OK"
        markUpdated()
        log("codex api: 200 OK")
        codexState.finishRefresh()
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
