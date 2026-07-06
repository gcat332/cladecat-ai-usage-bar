import Foundation

let claudeUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
let claudeUserAgent = "claude-code/2.1.138"
let claudeBeta = "oauth-2025-04-20"
let claudeKeychainService = "Claude Code-credentials"

let claudeOAuthTokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
let claudeOAuthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

let codexUsageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
let codexUserAgent = "codex_cli_rs"
let codexOAuthTokenURL = URL(string: "https://auth.openai.com/oauth/token")!
let codexOAuthClientID = "app_EMoamEEZ73f0CkXaXp7hrann"

let pollInterval: TimeInterval = 180
let backoffMax: TimeInterval = 900

let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("ClaudeCat")
let customIconURL = appSupportDir.appendingPathComponent("icon.png")
