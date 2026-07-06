import Foundation

struct ProviderRefreshState {
    let baseInterval: TimeInterval
    let maxInterval: TimeInterval
    var interval: TimeInterval
    var isRefreshing = false
    var didAttemptTokenRefresh = false
    var cooldownUntil: Date?

    init(baseInterval: TimeInterval, maxInterval: TimeInterval, cooldownUntil: Date? = nil) {
        self.baseInterval = baseInterval
        self.maxInterval = maxInterval
        self.interval = baseInterval
        self.cooldownUntil = cooldownUntil
    }

    mutating func beginRefresh(now: Date = Date()) -> Bool {
        guard !isRefreshing else { return false }
        if let cooldownUntil, now < cooldownUntil { return false }
        isRefreshing = true
        didAttemptTokenRefresh = false
        return true
    }

    mutating func finishRefresh() {
        isRefreshing = false
    }

    mutating func markTokenRefreshAttempted() {
        didAttemptTokenRefresh = true
    }

    mutating func applyRateLimit(retryAfter: TimeInterval?, now: Date = Date()) -> TimeInterval {
        if let retryAfter {
            interval = min(max(retryAfter + 15, baseInterval), 3600)
        } else {
            interval = min(max(interval * 2, baseInterval), maxInterval)
        }
        cooldownUntil = now.addingTimeInterval(interval)
        return interval
    }

    mutating func applyTokenRefreshFailure(statusCode: Int, retryAfter: TimeInterval?, now: Date = Date()) -> TimeInterval? {
        guard statusCode == 429 else { return nil }
        return applyRateLimit(retryAfter: retryAfter, now: now)
    }

    mutating func resetInterval() {
        interval = baseInterval
        cooldownUntil = nil
    }
}
