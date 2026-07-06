import Foundation

struct UsageWindow: Decodable {
    let utilization: Double?
    let resets_at: String?
}

struct ClaudeUsageResponse: Decodable {
    let five_hour: UsageWindow?
    let seven_day: UsageWindow?
}

struct OAuthRefreshResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
}

struct OAuthRefreshFailure {
    let message: String
    let statusCode: Int
    let retryAfter: TimeInterval?
}

struct CodexTokens: Decodable {
    let access_token: String?
    let account_id: String?
}

struct CodexAuthFile: Decodable {
    let tokens: CodexTokens?
}

struct CodexWindow: Decodable {
    let used_percent: Double?
    let reset_at: Double?
    let limit_window_seconds: Double?
}

struct CodexRateLimit: Decodable {
    let primary_window: CodexWindow?
    let secondary_window: CodexWindow?
}

struct CodexUsageResponse: Decodable {
    let rate_limit: CodexRateLimit?
}

struct CodexRefreshResponse: Decodable {
    let access_token: String?
    let id_token: String?
    let refresh_token: String?
}
